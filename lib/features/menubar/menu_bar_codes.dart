import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/permissions.dart';
import '../../core/result.dart';
import '../../core/security_core.dart';
import '../cache/offline_cache.dart';
import '../codes/code_models.dart';
import '../codes/codes_repository.dart' as repo;
import '../codes/secret_handle.dart';
import '../groups/group_models.dart';
import 'menu_bar_model.dart';

/*
 * 選單列要列出所有群組的驗證碼，所以每個群組都要有清單與金鑰（主畫面只載入目前看的群組）。
 * 先用離線快取補上（不用連網、不會記「查看金鑰」紀錄），選單打開時太舊的才重新讀取；
 * 只有「查看驗證碼」權限的由網站產碼，選單開著時跨過 30 秒的週期才重新取得。
 * 金鑰放在 Rust 記憶體裡每個群組自己的一格（scope），這裡只有 SecretHandle；
 * 加密群組鎖定、換使用者或 App 鎖定時整個丟掉（Rust 那一格跟著歸零），解鎖後再從離線快取放回來。
 */
class MenuBarCodes extends ChangeNotifier {
  MenuBarCodes({required this.cache}) {
    // App 鎖定或解鎖：Rust 已經清掉金鑰，整個重來（解鎖後下一次 refresh 從離線快取放回來）
    SecretSeal.sealed.addListener(() => reset(_uid));
  }

  final OfflineCache cache;

  // 清單與金鑰多久重新讀取一次（選單打開時才檢查）
  static const _maxAge = Duration(minutes: 5);
  static const _retryAfter = Duration(seconds: 30);
  // 伺服器產碼依 30 秒的週期邊界重新取得，過了邊界稍等一下（同 CodesController）
  static const _serverStep = 30000;
  static const _serverDelay = 500;
  // 取得失敗後隔一段時間才重試，選單開著時不會每秒打一次
  static const _serverRetry = 5000;

  String? _uid;
  final Map<String, _Entry> _entries = {};

  Map<String, MenuGroupData> get data => {for (final e in _entries.entries) e.key: e.value.data};

  /// 換使用者、登出或關掉選單列時清掉
  void reset(String? uid) {
    _uid = uid;
    if (_entries.isEmpty) return;
    for (final entry in _entries.values) {
      entry.dispose();
    }
    _entries.clear();
    notifyListeners();
  }

  /// 資料庫通知這個群組的驗證碼變了：下次選單打開時（開著的話馬上）重新讀取
  void markStale(String gid) {
    final entry = _entries[gid];
    if (entry == null) return;
    entry.loadedAt = 0;
    notifyListeners();
  }

  /// network 為 false 時只從離線快取補上還沒有的群組；為 true 時也重新讀取太舊的資料與伺服器產碼
  void refresh({required String uid, required List<GroupSummary> groups, required int? vaultKeyId, required bool network}) {
    if (_uid != uid) reset(uid);
    final ids = groups.map((g) => g.id).toSet();
    final removed = _entries.keys.where((id) => !ids.contains(id)).toList();
    for (final id in removed) {
      _entries.remove(id)?.dispose();
    }
    if (removed.isNotEmpty) notifyListeners();

    final now = DateTime.now().millisecondsSinceEpoch;
    for (final group in groups) {
      // 解不開的加密群組不讀（同 CodesController.locked）
      final key = group.encrypted ? vaultKeyId : null;
      if (group.encrypted && (!group.isOwner || key == null)) {
        final removedEntry = _entries.remove(group.id);
        if (removedEntry != null) {
          removedEntry.dispose();
          notifyListeners();
        }
        continue;
      }
      final signature = '${group.permissions}|${group.encrypted}|$key';
      var entry = _entries[group.id];
      if (entry == null || entry.signature != signature) {
        entry?.dispose();
        entry = _Entry(signature);
        _entries[group.id] = entry;
      }
      if (entry.loading) continue;
      final needCache = entry.data.accounts == null && !entry.triedCache;
      final needNetwork = network && now - entry.loadedAt >= _maxAge.inMilliseconds;
      if (needCache || needNetwork) {
        unawaited(_load(uid, group, entry, network: network));
      } else if (network) {
        _refreshServer(group, entry, now);
      }
    }
  }

  bool _current(String uid, String gid, _Entry entry) => _uid == uid && identical(_entries[gid], entry);

  Future<void> _load(String uid, GroupSummary group, _Entry entry, {required bool network}) async {
    entry.loading = true;
    try {
      if (entry.data.accounts == null && !entry.triedCache) {
        entry.triedCache = true;
        final cached = await cache.loadGroupData(uid, group.id);
        if (!_current(uid, group.id, entry)) return;
        if (cached != null) {
          final secrets = repo.restoreGroupSecrets(entry.scope, cached.sealedSecrets, encrypted: group.encrypted) ?? const {};
          entry.data = MenuGroupData(
            accounts: cached.accounts.map(GroupAccount.fromJson).toList(),
            secrets: secrets,
            server: entry.data.server,
          );
          notifyListeners();
        }
      }
      if (!network) return;

      final result = await repo.loadGroupAccountsRaw(group.id);
      if (!_current(uid, group.id, entry)) return;
      entry.loadedAt = DateTime.now().millisecondsSinceEpoch;
      switch (result) {
        case Ok(:final data):
          final list = data.map(GroupAccount.fromJson).toList();
          var secrets = <String, SecretHandle>{};
          String? sealedCache;
          if (list.any((a) => hasPermission(a.permissions, GroupPermission.viewSecrets))) {
            final secretsResult = await repo.loadGroupSecrets(group.id, scope: entry.scope, encrypted: group.encrypted);
            if (!_current(uid, group.id, entry)) return;
            if (secretsResult case Ok(data: final value)) {
              secrets = value.handles;
              sealedCache = value.sealedCache;
            } else if (entry.data.accounts != null) {
              // 金鑰讀不到時保留原本的資料
              return;
            }
          }
          entry.data = MenuGroupData(accounts: list, secrets: secrets, server: entry.data.server);
          unawaited(cache.saveGroupData(
            uid,
            group.id,
            CachedGroupData(accounts: data, sealedSecrets: sealedCache, savedAt: entry.loadedAt),
          ));
          notifyListeners();
          _refreshServer(group, entry, entry.loadedAt);
        case Err(:final message):
          // 失敗時半分鐘後再試；連不上時繼續用快取的資料，完全沒有資料才顯示失敗
          entry.loadedAt -= _maxAge.inMilliseconds - _retryAfter.inMilliseconds;
          if (entry.data.accounts == null) {
            entry.data = MenuGroupData(error: message);
            notifyListeners();
          }
      }
    } finally {
      if (identical(_entries[group.id], entry)) entry.loading = false;
    }
  }

  // 沒有金鑰的（只有「查看驗證碼」）才需要伺服器產碼；加密群組伺服器不產碼
  void _refreshServer(GroupSummary group, _Entry entry, int now) {
    final data = entry.data;
    final accounts = data.accounts;
    if (group.encrypted || accounts == null || entry.serverLoading) return;
    if (!accounts.any((a) => !data.secrets.containsKey(a.id))) return;
    final server = data.server;
    if (server != null) {
      final serverNow = now + server.offsetMs - _serverDelay;
      if (serverNow ~/ _serverStep <= server.at ~/ _serverStep) return;
    }
    if (now - entry.serverTriedAt < _serverRetry) return;
    unawaited(_loadServer(group, entry));
  }

  Future<void> _loadServer(GroupSummary group, _Entry entry) async {
    final uid = _uid;
    if (uid == null) return;
    entry.serverLoading = true;
    entry.serverTriedAt = DateTime.now().millisecondsSinceEpoch;
    try {
      final result = await repo.loadGroupCodes(group.id);
      if (!_current(uid, group.id, entry)) return;
      if (result case Ok(:final data)) {
        final current = entry.data;
        entry.data = MenuGroupData(accounts: current.accounts, secrets: current.secrets, server: data, error: current.error);
        notifyListeners();
      }
    } finally {
      entry.serverLoading = false;
    }
  }
}

class _Entry {
  _Entry(this.signature);

  // 權限、加密與金鑰變了就整個換新的
  final String signature;
  // Rust 記憶體裡這個群組的那一格
  final String scope = newSecretScope('menu');
  MenuGroupData data = const MenuGroupData();
  int loadedAt = 0;
  bool loading = false;
  bool triedCache = false;
  bool serverLoading = false;
  int serverTriedAt = 0;

  // 不再使用：Rust 那一格歸零
  void dispose() => clearSecretScope(scope);
}
