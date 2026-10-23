import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/result.dart';
import '../cache/offline_cache.dart';
import '../sync/live_sync.dart';
import 'group_models.dart';
import 'groups_repository.dart' as repo;
import 'manage/group_rules.dart';

/*
 * 側欄的群組清單與邀請（同網站 CodeClient 的群組切換）。
 * 目前看的群組記在這台裝置；記住的群組已不在（被刪掉、被移出）時改用預設群組（沒有就第一個）。
 * 跟資料庫同步（網站或其他裝置改了）：
 * - 即時通知（LiveSync）：群組清單變了重新讀群組，邀請變了重新讀邀請，驗證碼變了通知那個群組的 CodesController
 * - 備援：每 60 秒、App 回到前景（桌面是視窗取得焦點）、即時通知斷線重連時，背景同步一次全部
 * 背景同步不顯示讀取中、讀不到時保留原本的資料，內容沒變就不通知畫面。
 */
class GroupsController extends ChangeNotifier with WidgetsBindingObserver {
  GroupsController({required this.cache});

  final OfflineCache cache;

  static const _scopeKey = 'securibit:codeScope';
  static const pollInterval = Duration(seconds: 60);
  // 回到前景時，離上次讀取不到這麼久就不重讀（桌面切換視窗很頻繁）
  static const _resumeThrottle = Duration(seconds: 10);

  Timer? _poll;
  bool _observing = false;
  DateTime? _syncedAt;
  int _reorderSeq = 0;
  // 正在送出的調整順序（這時背景同步讀到的還是舊順序，不套用）
  int _moving = 0;
  // 只有最後一次讀取的結果算數
  int _loadSeq = 0;
  // 上次讀到的原始資料，背景同步時內容沒變就不通知畫面
  String? _raw;

  late final LiveSync _live = LiveSync(onSignals: _onSignals, onReconnected: () => unawaited(syncAll()));
  final _codesSignals = StreamController<CodesSignal>.broadcast();

  /// 要重新讀取某個群組驗證碼的通知（即時通知與背景同步）
  Stream<CodesSignal> get codesSignals => _codesSignals.stream;

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
    _raw = null;
    invitations = const [];
    error = null;
    _startPolling();
    _live.start(userId);
    try {
      final prefs = await SharedPreferences.getInstance();
      _remembered = prefs.getString(_scopeKey) ?? '';
    } catch (_) {
      _remembered = '';
    }
    // 先顯示離線快取的群組（開 App 馬上看得到驗證碼），再在背景向伺服器讀；沒有快取才顯示讀取中
    final cached = await cache.loadGroups(userId);
    if (uid != userId) return;
    if (cached != null && groups == null) {
      groups = repo.parseGroups(cached);
      notifyListeners();
      await reload(quiet: true);
      return;
    }
    await reload();
  }

  void clear() {
    _stopPolling();
    _live.stop();
    uid = null;
    groups = null;
    _raw = null;
    invitations = const [];
    error = null;
    offline = false;
    notifyListeners();
  }

  /// 重新讀取群組與邀請。
  /// quiet：背景同步，不顯示讀取中，讀不到時保留原本的資料，內容沒變就不通知畫面；invitations 為 false 時不讀邀請
  Future<void> reload({bool quiet = false, bool invitations = true}) async {
    final userId = uid;
    if (userId == null) return;
    final seq = ++_loadSeq;
    if (!quiet) {
      loading = true;
      notifyListeners();
    }

    final result = await repo.loadMyGroupsRaw();
    if (uid != userId || seq != _loadSeq) return;
    // 背景同步讀不到就保留原本的資料；正在調整順序時讀到的是舊順序（調整完資料庫會再通知一次）
    if (quiet && (_moving > 0 || (result is Err && groups != null))) {
      // 連不上伺服器：資料保留，標成離線（畫面提示無法同步）；連回來時下一次同步會拿掉
      final lostConnection = _moving == 0 && !offline && result is Err<List<Map<String, dynamic>>> && result.offline;
      if (lostConnection) offline = true;
      // 被這次取代的一般讀取顯示的讀取中要收起來
      if (loading || lostConnection) {
        loading = false;
        notifyListeners();
      }
      return;
    }
    switch (result) {
      case Ok(:final data):
        final raw = jsonEncode(data);
        final changed = raw != _raw || offline || error != null || loading;
        _raw = raw;
        if (changed) {
          groups = repo.parseGroups(data);
          offline = false;
          error = null;
          unawaited(cache.saveGroups(userId, data));
        }
        if (quiet && !changed) {
          if (invitations) unawaited(_loadInvitations(userId));
          return;
        }
      case Err(:final message, offline: final isOffline):
        final cached = isOffline ? await cache.loadGroups(userId) : null;
        if (uid != userId) return;
        if (cached != null) {
          groups = repo.parseGroups(cached);
          _raw = null;
          offline = true;
          error = null;
        } else {
          error = message;
          offline = isOffline;
        }
    }
    loading = false;
    notifyListeners();
    if (!offline && invitations) unawaited(_loadInvitations(userId));
  }

  /// 重新讀取收到的邀請
  Future<void> refreshInvitations() async {
    final userId = uid;
    if (userId == null) return;
    await _loadInvitations(userId);
  }

  /// 背景同步全部：群組、邀請、目前群組的驗證碼（輪詢、回到前景、即時通知斷線重連時）
  Future<void> syncAll() async {
    if (uid == null) return;
    _syncedAt = DateTime.now();
    final gid = selectedId;
    if (gid != null) _codesSignals.add(CodesSignal(gid, confirmed: false));
    await reload(quiet: true);
  }

  // 即時通知：只重新讀變了的部分
  void _onSignals(SyncBatch batch) {
    if (uid == null) return;
    if (batch.groups) unawaited(reload(quiet: true, invitations: false));
    if (batch.invitations) unawaited(refreshInvitations());
    batch.codes.forEach((gid, secrets) => _codesSignals.add(CodesSignal(gid, secrets: secrets)));
  }

  void _startPolling() {
    _poll?.cancel();
    _poll = Timer.periodic(pollInterval, (_) => unawaited(syncAll()));
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
    final last = _syncedAt;
    if (last != null && DateTime.now().difference(last) < _resumeThrottle) return;
    unawaited(syncAll());
  }

  @override
  void dispose() {
    _stopPolling();
    _live.stop();
    unawaited(_codesSignals.close());
    super.dispose();
  }

  Future<void> _loadInvitations(String userId) async {
    final result = await repo.loadMyInvitations();
    if (uid != userId) return;
    // 邀請讀不到不影響主要功能，不跳錯誤；沒變就不通知畫面
    if (result case Ok(:final data)) {
      if (_sameInvitations(invitations, data)) return;
      invitations = data;
      notifyListeners();
    }
  }

  static bool _sameInvitations(List<Invitation> a, List<Invitation> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id || a[i].groupName != b[i].groupName || a[i].memberCount != b[i].memberCount) return false;
    }
    return true;
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
    _moving++;
    final result = await repo.reorderMyGroups(ids);
    _moving--;
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
