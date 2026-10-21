import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/result.dart';
import '../cache/offline_cache.dart';
import 'group_models.dart';
import 'groups_repository.dart' as repo;

/*
 * 側欄的群組清單與邀請（同網站 CodeClient 的群組切換）。
 * 目前看的群組記在這台裝置；記住的群組已不在時改用預設群組（沒有就第一個）。
 */
class GroupsController extends ChangeNotifier {
  GroupsController({required this.cache});

  final OfflineCache cache;

  static const _scopeKey = 'securibit:codeScope';

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

  Future<void> start(String userId) async {
    if (uid == userId && groups != null) return;
    uid = userId;
    groups = null;
    invitations = const [];
    error = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      _remembered = prefs.getString(_scopeKey) ?? '';
    } catch (_) {
      _remembered = '';
    }
    await reload();
  }

  void clear() {
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

  Future<void> _loadInvitations(String userId) async {
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
