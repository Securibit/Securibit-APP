import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../core/permissions.dart';
import '../../core/result.dart';
import '../../core/security_core.dart';
import '../cache/offline_cache.dart';
import '../groups/group_models.dart';
import '../sync/live_sync.dart';
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
 * 網站或其他裝置改了這個群組（signals，見 GroupsController）時背景同步：只重新讀清單，
 * 金鑰變了、有新的或新拿到「查看金鑰」的才重新讀金鑰；不顯示讀取中，選取、搜尋、類別、排序模式都保留。
 * 讀取一律排隊（_serial），不會有舊的結果蓋掉新的。
 */
class CodesController extends ChangeNotifier {
  CodesController({
    required this.group,
    required this.uid,
    required this.vaultKeyId,
    required this.cache,
    Stream<CodesSignal>? signals,
  }) {
    SecretSeal.sealed.addListener(_onSealChanged);
    _signals = signals?.where((s) => s.groupId == group.id).listen((s) => sync(secretsChanged: s.secrets));
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
  // 顯示的金鑰來自離線快取（連回來時要重新讀）；只是同步時斷線則還是記憶體裡原本的金鑰
  bool _fromCache = false;

  String keyword = '';
  String? category;
  String? selectedId;
  // 排序模式（同網站的「調整順序」）：顯示全部，不套用搜尋與類別篩選
  bool sorting = false;
  // 連續按上下移時，只有最後一次的結果算數
  int _reorderSeq = 0;
  // 正在送出的調整順序（這時背景同步讀到的還是舊順序，不套用）
  int _reordering = 0;

  StreamSubscription<CodesSignal>? _signals;
  Future<void> _queue = Future.value();
  bool _syncQueued = false;
  bool _syncSecrets = false;
  // 上次讀到的清單（原始 JSON）：背景同步時沒變就不通知畫面
  String? _accountsRaw;
  // 上次讀到的金鑰封起來的密文：只重新讀清單時一起存進離線快取
  String? _sealedCache;
  // 上次讀金鑰後還是沒有金鑰的那幾筆：不要每次同步都為了它們重新讀金鑰
  Set<String> _unresolved = const {};
  // 自己新增或改了金鑰（接著會重新讀金鑰）的時間
  DateTime? _ownSecretsAt;
  static const _ownEchoWindow = Duration(seconds: 5);

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

  // 排序、清空要群組層級的「管理驗證碼」；兩筆以上才有順序可以調
  bool get canSort => canAdd && (accounts?.length ?? 0) >= 2;

  bool get canClear => canAdd && (accounts?.isNotEmpty ?? false);

  // 單筆權限覆寫要群組層級的「管理身分組」
  bool get canOverwrite => hasPermission(group.permissions, GroupPermission.manageRoles) && !offline;

  // 匯出、複製到其他群組要拿得到正確的金鑰（有「查看金鑰」）
  bool canExport(GroupAccount account) => secretOf(account)?.valid ?? false;

  bool canCopy(GroupAccount account) => canExport(account) && !offline;

  /// 全部匯出：拿得到正確金鑰的那些（依畫面順序）
  List<GroupAccount> get exportable => ordered.where(canExport).toList();

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
    if (sorting) return ordered;
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
  Future<void> load() => _serial(_load);

  Future<void> _load() async {
    error = null;
    _notify();

    final result = await repo.loadGroupAccountsRaw(group.id);
    if (_disposed) return;
    switch (result) {
      case Ok(:final data):
        await _applyWithSecrets(data, quiet: false);
      case Err(:final message, offline: final isOffline):
        final cached = isOffline ? await cache.loadGroupData(uid, group.id) : null;
        if (_disposed) return;
        if (cached != null) {
          accounts = cached.accounts.map(GroupAccount.fromJson).toList();
          secrets = repo.restoreGroupSecrets(_scope, cached.sealedSecrets, encrypted: group.encrypted) ?? const {};
          offline = true;
          _fromCache = true;
          _accountsRaw = null;
        } else {
          error = message;
          offline = isOffline;
          accounts ??= const [];
        }
    }
    _notify();
  }

  /// 套用讀到的清單並重新讀金鑰（有「查看金鑰」的才讀，會記一筆「查看金鑰」）。
  /// quiet（背景同步）時金鑰讀不到就保留原本的資料，不跳錯誤
  Future<void> _applyWithSecrets(List<Map<String, dynamic>> data, {required bool quiet}) async {
    final list = data.map(GroupAccount.fromJson).toList();
    var handles = <String, SecretHandle>{};
    String? sealedCache;
    if (list.any((a) => hasPermission(a.permissions, GroupPermission.viewSecrets))) {
      final secretsResult = await repo.loadGroupSecrets(group.id, scope: _scope, encrypted: group.encrypted);
      if (_disposed) return;
      switch (secretsResult) {
        case Ok(data: final value):
          // App 剛好鎖定：金鑰沒放進記憶體，解鎖後從離線快取放回來
          if (quiet && value.sealed) return;
          handles = value.handles;
          sealedCache = value.sealedCache;
        case Err(:final message):
          if (quiet) return;
          clearSecretScope(_scope);
          error = '載入金鑰失敗：$message';
      }
    } else {
      clearSecretScope(_scope);
    }
    // 背景同步時連線恢復了：拿掉離線時的錯誤
    if (quiet && offline) error = null;
    accounts = list;
    secrets = handles;
    offline = false;
    _fromCache = false;
    _accountsRaw = jsonEncode(data);
    _sealedCache = sealedCache;
    _unresolved = {for (final a in list) if (hasPermission(a.permissions, GroupPermission.viewSecrets) && !handles.containsKey(a.id)) a.id};
    unawaited(cache.saveGroupData(
      uid,
      group.id,
      CachedGroupData(accounts: data, sealedSecrets: sealedCache, savedAt: DateTime.now().millisecondsSinceEpoch),
    ));
    _restartServerCodes();
    _notify();
  }

  /// 背景同步（網站或其他裝置改了、輪詢、回到前景）；secretsChanged：資料庫說金鑰變了。
  /// 連續的同步合成一次；讀不到時保留原本的資料
  void sync({bool secretsChanged = false}) {
    if (_disposed || locked) return;
    _syncSecrets = _syncSecrets || secretsChanged;
    if (_syncQueued) return;
    _syncQueued = true;
    unawaited(_serial(() async {
      _syncQueued = false;
      final withSecrets = _syncSecrets;
      _syncSecrets = false;
      await _sync(withSecrets);
    }));
  }

  Future<void> _sync(bool secretsChanged) async {
    // 還沒讀過（第一次讀取會讀到最新的）、App 鎖定中（解鎖回到前景時會再同步）、正在調整順序（調整完資料庫會再通知一次）
    if (accounts == null || SecretSeal.sealed.value || _reordering > 0) return;
    // 自己剛新增或改了金鑰、也已經重新讀過：資料庫回傳的這次通知不用再讀一次（少記一筆「查看金鑰」）
    var withSecrets = secretsChanged;
    final own = _ownSecretsAt;
    if (withSecrets && own != null && DateTime.now().difference(own) < _ownEchoWindow) {
      withSecrets = false;
      _ownSecretsAt = null;
    }
    final result = await repo.loadGroupAccountsRaw(group.id);
    if (_disposed || _reordering > 0 || SecretSeal.sealed.value) return;
    final data = result.dataOrNull;
    if (data == null) {
      // 連不上伺服器：畫面上的驗證碼照舊，標成離線（提示無法同步、暫停編輯）
      if (result case Err(offline: true) when !offline) {
        offline = true;
        _notify();
      }
      return;
    }
    final list = data.map(GroupAccount.fromJson).toList();
    final ids = {for (final a in list) a.id};
    final viewable = {for (final a in list) if (hasPermission(a.permissions, GroupPermission.viewSecrets)) a.id};
    // 要重新讀金鑰：金鑰變了、還在用離線快取、有新的（或新拿到「查看金鑰」的）、
    // 有被拿掉「查看金鑰」的（重新讀一次，離線快取裡也不要再留著它的金鑰）
    final needSecrets = withSecrets ||
        _fromCache ||
        viewable.any((id) => !secrets.containsKey(id) && !_unresolved.contains(id)) ||
        secrets.keys.any((id) => ids.contains(id) && !viewable.contains(id));
    if (needSecrets) {
      await _applyWithSecrets(data, quiet: true);
      return;
    }
    final raw = jsonEncode(data);
    // 連回來了：拿掉離線提示
    final reconnected = offline;
    offline = false;
    if (raw == _accountsRaw) {
      if (reconnected) _notify();
      return;
    }
    _applyList(list);
    _accountsRaw = raw;
    unawaited(cache.saveGroupData(
      uid,
      group.id,
      CachedGroupData(accounts: data, sealedSecrets: _sealedCache, savedAt: DateTime.now().millisecondsSinceEpoch),
    ));
    _notify();
  }

  // 排隊執行讀取，前一個做完才做下一個
  Future<void> _serial(Future<void> Function() task) {
    final next = _queue.then((_) async {
      if (!_disposed) await task();
    });
    _queue = next.catchError((Object _) {});
    return next;
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

  void setSorting(bool value) {
    sorting = value;
    _notify();
  }

  // ---------- 修改（回傳錯誤訊息，成功為 null） ----------

  Future<String?> add(TotpInput input) async {
    final result = await repo.addGroupAccount(group.id, input, encrypted: group.encrypted);
    if (result case Err(:final message)) return message;
    _ownSecretsAt = DateTime.now();
    await load();
    final ids = result.dataOrNull;
    if (ids != null && ids.isNotEmpty) select(ids.first);
    return null;
  }

  /// secret 為 null 代表不修改金鑰
  Future<String?> update(GroupAccount account, TotpInput input, {String? secret}) async {
    final result = await repo.updateGroupAccount(account.id, input, secret: secret, encrypted: group.encrypted);
    if (result case Err(:final message)) return message;
    if (secret != null) _ownSecretsAt = DateTime.now();
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

  /// 排序模式的上下移：和相鄰的交換（offset −1 往上、1 往下），先換畫面，失敗再換回來
  Future<String?> reorder(int index, int offset) async {
    final previous = accounts;
    final list = ordered;
    if (previous == null || !canSwapAccounts(list, index, offset)) return null;
    final next = swapAccounts(list, index, offset);
    accounts = next;
    _notify();
    final seq = ++_reorderSeq;
    _reordering++;
    final result = await repo.reorderGroupAccounts(group.id, next.map((a) => a.id).toList());
    _reordering--;
    if (_disposed || seq != _reorderSeq) return null;
    if (result case Err(:final message)) {
      accounts = previous;
      _notify();
      return message;
    }
    return null;
  }

  /// 清空全部（只會刪掉我能管理的那些）；成功回傳刪掉的筆數
  Future<Result<int>> clear() async {
    final result = await repo.clearGroupAccounts(group.id);
    if (result is Ok<int>) await _serial(_reloadList);
    return result;
  }

  /// 複製一份到其他群組（之後兩邊各自獨立）；目標是加密群組時要先解鎖，金鑰會用加密密碼加密
  Future<String?> copyTo(GroupAccount account, GroupSummary target) async {
    final secret = secretOf(account)?.reveal();
    if (secret == null) return '拿不到這筆驗證碼的金鑰，無法複製';
    final input = TotpInput(
      name: account.name,
      secret: secret,
      category: account.category,
      digits: account.digits,
      period: account.period,
      algorithm: account.algorithm,
    );
    final result = await repo.addGroupAccount(target.id, input, encrypted: target.encrypted);
    if (result case Err(:final message)) return message;
    return null;
  }

  // 只重新讀清單，不重新讀金鑰（讀金鑰會多記一筆「查看金鑰」）
  Future<void> _reloadList() async {
    final result = await repo.loadGroupAccountsRaw(group.id);
    if (_disposed) return;
    final data = result.dataOrNull;
    if (data == null) {
      await _load();
      return;
    }
    _applyList(data.map(GroupAccount.fromJson).toList());
    _accountsRaw = jsonEncode(data);
    _notify();
  }

  // 換上新的清單，金鑰沿用；不見的那幾筆把金鑰歸零
  void _applyList(List<GroupAccount> list) {
    final ids = list.map((a) => a.id).toSet();
    for (final id in secrets.keys.where((id) => !ids.contains(id))) {
      removeSecret(_scope, id);
    }
    secrets = {for (final entry in secrets.entries) if (ids.contains(entry.key)) entry.key: entry.value};
    accounts = list;
    _restartServerCodes();
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
    unawaited(_signals?.cancel());
    _serverTimer?.cancel();
    SecretSeal.sealed.removeListener(_onSealChanged);
    clearSecretScope(_scope);
    super.dispose();
  }
}

/// 排序模式：第 index 筆能不能和相鄰的交換（offset −1 往上、1 往下）。
/// 釘選的和未釘選的不互換，釘選的固定排在最上面（同網站 GroupCodes 的 canSwap）
bool canSwapAccounts(List<GroupAccount> ordered, int index, int offset) {
  final target = index + offset;
  if (index < 0 || index >= ordered.length || target < 0 || target >= ordered.length) return false;
  return ordered[index].pinned == ordered[target].pinned;
}

/// 把第 index 筆和相鄰的交換，回傳新的順序（不檢查，先用 canSwapAccounts 確認）
List<GroupAccount> swapAccounts(List<GroupAccount> ordered, int index, int offset) {
  final next = [...ordered];
  final target = index + offset;
  final moving = next[index];
  next[index] = next[target];
  next[target] = moving;
  return next;
}

/// 「複製到其他群組」能選的群組：有群組層級的「管理驗證碼」，不含來源群組（同網站 ShareToGroupModal）
List<GroupSummary> copyTargetGroups(List<GroupSummary> groups, String excludeId) =>
    groups.where((g) => g.id != excludeId && hasPermission(g.permissions, GroupPermission.manageCodes)).toList();
