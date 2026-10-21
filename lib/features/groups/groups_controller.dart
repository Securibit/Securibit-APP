import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/result.dart';
import '../cache/offline_cache.dart';
import 'group_models.dart';
import 'groups_repository.dart' as repo;
import 'manage/group_rules.dart';

/*
 * 側欄的群組清單與邀請（同網站 CodeClient 的群組切換）。
 * 目前看的群組記在這台裝置；記住的群組已不在時改用預設群組（沒有就第一個）。
 * 收到的邀請每 60 秒、以及 App 回到前景時重新讀一次（側欄顯示未處理的數字）。
 */
class GroupsController extends ChangeNotifier with WidgetsBindingObserver {
  GroupsController({required this.cache});

  final OfflineCache cache;

  static const _scopeKey = 'securibit:codeScope';
  static const invitationPollInterval = Duration(seconds: 60);
  // 回到前景時，離上次讀取不到這麼久就不重讀（桌面切換視窗很頻繁）
  static const _resumeThrottle = Duration(seconds: 10);

  Timer? _poll;
  bool _observing = false;
  DateTime? _invitationsAt;
  int _reorderSeq = 0;

  String? uid;
  List<GroupSummary>? groups;
  List<Invitation> invitations = const [];
  String? error;
  // 目前顯示的是離線快取
  bool offline = false;
  bool loading = false;
  String _remembered = '';

  String? get selectedId {
    final list = groups;
    if (list == null || list.isEmpty) return null;
    if (list.any((g) => g.id == _remembered)) return _remembered;
    return (list.where((g) => g.isDefault).firstOrNull ?? list.first).id;
  }

  GroupSummary? get selected {
    final id = selectedId;
    return groups?.where((g) => g.id == id).firstOrNull;
  }

  /// 未處理的邀請數
  int get pendingInvitations => invitations.length;

  Future<void> start(String userId) async {
    if (uid == userId && groups != null) return;
    uid = userId;
    groups = null;
    invitations = const [];
    error = null;
    _startPolling();
    try {
      final prefs = await SharedPreferences.getInstance();
      _remembered = prefs.getString(_scopeKey) ?? '';
    } catch (_) {
      _remembered = '';
    }
    await reload();
  }

  void clear() {
    _stopPolling();
    uid = null;
    groups = null;
    invitations = const [];
    error = null;
    offline = false;
    notifyListeners();
  }

  /// 重新讀取群組與邀請
  Future<void> reload() async {
    final userId = uid;
    if (userId == null) return;
    loading = true;
    notifyListeners();

    final result = await repo.loadMyGroupsRaw();
    if (uid != userId) return;
    switch (result) {
      case Ok(:final data):
        groups = repo.parseGroups(data);
        offline = false;
        error = null;
        unawaited(cache.saveGroups(userId, data));
      case Err(:final message, offline: final isOffline):
        final cached = isOffline ? await cache.loadGroups(userId) : null;
        if (uid != userId) return;
        if (cached != null) {
          groups = repo.parseGroups(cached);
          offline = true;
          error = null;
        } else {
          error = message;
          offline = isOffline;
        }
    }
    loading = false;
    notifyListeners();
    if (!offline) unawaited(_loadInvitations(userId));
  }

  /// 重新讀取收到的邀請（輪詢、回到前景時）
  Future<void> refreshInvitations() async {
    final userId = uid;
    if (userId == null) return;
    await _loadInvitations(userId);
  }

  void _startPolling() {
    _poll?.cancel();
    _poll = Timer.periodic(invitationPollInterval, (_) => unawaited(refreshInvitations()));
    if (!_observing) {
      WidgetsBinding.instance.addObserver(this);
      _observing = true;
    }
  }

  void _stopPolling() {
    _poll?.cancel();
    _poll = null;
    if (_observing) {
      WidgetsBinding.instance.removeObserver(this);
      _observing = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final last = _invitationsAt;
    if (last != null && DateTime.now().difference(last) < _resumeThrottle) return;
    unawaited(refreshInvitations());
  }

  @override
  void dispose() {
    _stopPolling();
    super.dispose();
  }

  Future<void> _loadInvitations(String userId) async {
    _invitationsAt = DateTime.now();
    final result = await repo.loadMyInvitations();
    if (uid != userId) return;
    // 邀請讀不到不影響主要功能，不跳錯誤
    if (result case Ok(:final data)) {
      invitations = data;
      notifyListeners();
    }
  }

  void select(String gid) {
    _remembered = gid;
    notifyListeners();
    unawaited(SharedPreferences.getInstance().then((prefs) => prefs.setString(_scopeKey, gid)).catchError((_) => false));
  }

  /// 把群組往上（-1）或往下（+1）移一格：先換畫面，失敗再換回來（同網站 GroupsClient）。
  /// 回傳錯誤訊息，成功為 null
  Future<String?> move(String gid, int offset) async {
    final list = groups;
    if (list == null) return null;
    final ids = moveGroupIds(list.map((g) => g.id).toList(), gid, offset);
    if (ids == null) return null;
    final moved = [for (final id in ids) list.firstWhere((g) => g.id == id)];
    groups = moved;
    notifyListeners();
    final seq = ++_reorderSeq;
    final result = await repo.reorderMyGroups(ids);
    if (seq != _reorderSeq) return null;
    switch (result) {
      case Ok():
        final userId = uid;
        if (userId != null) unawaited(cache.saveGroups(userId, [for (final g in moved) g.toJson()]));
        return null;
      case Err(:final message):
        // 這段時間重新讀取過就用讀到的，不要蓋回去
        if (identical(groups, moved)) {
          groups = list;
          notifyListeners();
        }
        return message;
    }
  }

  /// 接受或拒絕邀請；回傳錯誤訊息，成功為 null。接受後切到那個群組
  Future<String?> respond(Invitation invitation, {required bool accept}) async {
    final result = await repo.respondInvitation(invitation.id, accept: accept);
    switch (result) {
      case Ok(:final data):
        invitations = invitations.where((i) => i.id != invitation.id).toList();
        notifyListeners();
        if (accept) {
          await reload();
          if (data != null) select(data);
        }
        return null;
      case Err(:final message):
        return message;
    }
  }
}
