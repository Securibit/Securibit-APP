import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/permissions.dart';
import '../../core/result.dart';
import '../../core/security_core.dart';
import '../cache/offline_cache.dart';
import '../groups/group_models.dart';
import 'code_models.dart';
import 'codes_repository.dart' as repo;
import 'secret_handle.dart';
import 'totp/categories.dart';
import 'totp/totp_params.dart';

/*
 * 一個群組的驗證碼（同網站 GroupCodes）：清單、金鑰、伺服器產碼、搜尋與類別篩選、選中的那一筆。
 * 切換群組或解鎖時整個換一個新的 controller（見 CodesScope）。
 * 金鑰放在 Rust 記憶體裡自己的一格（scope），這裡只有指向它的 SecretHandle；controller 丟掉時那一格跟著歸零。
 * App 鎖定時 Rust 清掉全部金鑰，解鎖後從離線快取的密文放回來（沒有快取才重新連線）。
 */
class CodesController extends ChangeNotifier {
  CodesController({required this.group, required this.uid, required this.vaultKeyId, required this.cache}) {
    SecretSeal.sealed.addListener(_onSealChanged);
    if (!locked) unawaited(load());
  }

  final GroupSummary group;
  final String uid;
  // 加密群組解鎖後的金鑰編號（金鑰本身在 Rust；其他群組為 null）
  final int? vaultKeyId;
  final OfflineCache cache;

  final String _scope = newSecretScope('codes');

  List<GroupAccount>? accounts;
  // 我有「查看金鑰」的金鑰 { id: 指向 Rust 裡金鑰的 handle }（加密群組已在 Rust 解密）
  Map<String, SecretHandle> secrets = const {};
  ServerCodes? server;
  String? error;
  // 顯示的是離線快取
  bool offline = false;

  String keyword = '';
  String? category;
  String? selectedId;

  Timer? _serverTimer;
  bool _serverFailed = false;
  bool _disposed = false;

  // 伺服器產碼依 30 秒的週期邊界重新取得（60 秒週期的邊界也一定是 30 秒的邊界）
  static const _refreshStep = 30000;
  // 過了邊界再稍等一下才打，避免伺服器時間還沒跨過去
  static const _refreshDelay = 500;

  // 加密群組：只有擁有者解鎖後才能看（其他人例如全站管理員解不開）
  bool get locked => group.encrypted && (!group.isOwner || vaultKeyId == null);

  // 群組層級的「管理驗證碼」才能新增
  bool get canAdd => hasPermission(group.permissions, GroupPermission.manageCodes) && !offline;

  bool canManage(GroupAccount account) => hasPermission(account.permissions, GroupPermission.manageCodes) && !offline;

  // 只有自己一個人的群組（例如預設群組）用個人的說法
  bool get solo => group.memberCount <= 1;

  List<String> get categories => collectCategories((accounts ?? const []).map((a) => a.category));

  String? get activeCategory => category != null && categories.contains(category) ? category : null;

  // 釘選的排最上面，其餘維持儲存的順序
  List<GroupAccount> get ordered {
    final list = accounts ?? const <GroupAccount>[];
    return [...list.where((a) => a.pinned), ...list.where((a) => !a.pinned)];
  }

  List<GroupAccount> get filtered {
    final q = keyword.trim().toLowerCase();
    final active = activeCategory;
    return ordered
        .where((a) =>
            (active == null || hasCategory(a.category, active)) &&
            (q.isEmpty || a.name.toLowerCase().contains(q) || parseCategories(a.category).any((c) => c.toLowerCase().contains(q))))
        .toList();
  }

  GroupAccount? get selected => accounts?.where((a) => a.id == selectedId).firstOrNull;

  // 寬視窗右欄顯示的那一筆：沒選、或選的那筆不見了（被刪掉、換群組）就是 null，右欄收起來
  String? get openId => selected?.id;

  SecretHandle? secretOf(GroupAccount account) => secrets[account.id];

  /// 讀取清單與金鑰；連不上時改用離線快取
  Future<void> load() async {
    error = null;
    _notify();

    final result = await repo.loadGroupAccountsRaw(group.id);
    if (_disposed) return;
    switch (result) {
      case Ok(:final data):
        final list = data.map(GroupAccount.fromJson).toList();
        var handles = <String, SecretHandle>{};
        String? sealedCache;
        if (list.any((a) => hasPermission(a.permissions, GroupPermission.viewSecrets))) {
          final secretsResult = await repo.loadGroupSecrets(group.id, scope: _scope, encrypted: group.encrypted);
          if (_disposed) return;
          switch (secretsResult) {
            case Ok(data: final value):
              handles = value.handles;
              sealedCache = value.sealedCache;
            case Err(:final message):
              clearSecretScope(_scope);
              error = '載入金鑰失敗：$message';
          }
        } else {
          clearSecretScope(_scope);
        }
        accounts = list;
        secrets = handles;
        offline = false;
        unawaited(cache.saveGroupData(
          uid,
          group.id,
          CachedGroupData(accounts: data, sealedSecrets: sealedCache, savedAt: DateTime.now().millisecondsSinceEpoch),
        ));
        _restartServerCodes();
      case Err(:final message, offline: final isOffline):
        final cached = isOffline ? await cache.loadGroupData(uid, group.id) : null;
        if (_disposed) return;
        if (cached != null) {
          accounts = cached.accounts.map(GroupAccount.fromJson).toList();
          secrets = repo.restoreGroupSecrets(_scope, cached.sealedSecrets, encrypted: group.encrypted) ?? const {};
          offline = true;
        } else {
          error = message;
          offline = isOffline;
          accounts ??= const [];
        }
    }
    _notify();
  }

  // App 鎖定：Rust 已經清掉金鑰，這裡也丟掉 handle；解鎖：從離線快取放回來
  void _onSealChanged() {
    if (_disposed || locked) return;
    if (SecretSeal.sealed.value) {
      secrets = const {};
      _serverTimer?.cancel();
      _notify();
    } else if (accounts != null) {
      unawaited(_restoreSecrets());
    }
  }

  Future<void> _restoreSecrets() async {
    final cached = await cache.loadGroupData(uid, group.id);
    if (_disposed || SecretSeal.sealed.value) return;
    final restored = cached == null ? null : repo.restoreGroupSecrets(_scope, cached.sealedSecrets, encrypted: group.encrypted);
    if (restored == null) {
      // 沒有快取（例如 Linux 沒有安全儲存）就重新讀取
      await load();
      return;
    }
    secrets = restored;
    _restartServerCodes();
    _notify();
  }

  // 沒有金鑰的（只有「查看驗證碼」）才需要伺服器產碼；加密群組伺服器不產碼
  void _restartServerCodes() {
    _serverTimer?.cancel();
    // 鎖定中不知道哪些有金鑰，解鎖放回金鑰後再決定
    if (SecretSeal.sealed.value) return;
    final needServer = !group.encrypted && (accounts ?? const []).any((a) => !secrets.containsKey(a.id));
    if (!needServer) {
      server = null;
      return;
    }
    _serverFailed = false;
    unawaited(_tickServer());
  }

  Future<void> _tickServer() async {
    final result = await repo.loadGroupCodes(group.id);
    if (_disposed) return;
    switch (result) {
      case Ok(:final data):
        server = data;
        _serverFailed = false;
        _notify();
      case Err(:final message):
        // 連續失敗只顯示一次，避免每 30 秒跳一次
        if (!_serverFailed) {
          _serverFailed = true;
          error = '取得驗證碼失敗：$message';
          _notify();
        }
    }
    final serverNow = DateTime.now().millisecondsSinceEpoch + (server?.offsetMs ?? 0);
    _serverTimer = Timer(
      Duration(milliseconds: _refreshStep - serverNow % _refreshStep + _refreshDelay),
      () => unawaited(_tickServer()),
    );
  }

  void setKeyword(String value) {
    keyword = value;
    _notify();
  }

  void setCategory(String? value) {
    category = value;
    _notify();
  }

  void select(String? id) {
    selectedId = id;
    _notify();
  }

  // ---------- 修改（回傳錯誤訊息，成功為 null） ----------

  Future<String?> add(TotpInput input) async {
    final result = await repo.addGroupAccount(group.id, input, encrypted: group.encrypted);
    if (result case Err(:final message)) return message;
    await load();
    final ids = result.dataOrNull;
    if (ids != null && ids.isNotEmpty) select(ids.first);
    return null;
  }

  /// secret 為 null 代表不修改金鑰
  Future<String?> update(GroupAccount account, TotpInput input, {String? secret}) async {
    final result = await repo.updateGroupAccount(account.id, input, secret: secret, encrypted: group.encrypted);
    if (result case Err(:final message)) return message;
    await load();
    return null;
  }

  Future<String?> togglePin(GroupAccount account) async {
    final result = await repo.setPinned(account.id, !account.pinned);
    if (result case Err(:final message)) return message;
    accounts = accounts?.map((a) => a.id == account.id ? a.copyWith(pinned: !account.pinned) : a).toList();
    _notify();
    return null;
  }

  Future<String?> delete(GroupAccount account) async {
    final result = await repo.deleteGroupAccount(account.id);
    if (result case Err(:final message)) return message;
    accounts = accounts?.where((a) => a.id != account.id).toList();
    secrets = {...secrets}..remove(account.id);
    removeSecret(_scope, account.id);
    if (selectedId == account.id) selectedId = null;
    _notify();
    return null;
  }

  void clearError() {
    error = null;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _serverTimer?.cancel();
    SecretSeal.sealed.removeListener(_onSealChanged);
    clearSecretScope(_scope);
    super.dispose();
  }
}
