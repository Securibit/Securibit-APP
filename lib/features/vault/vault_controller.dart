import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../core/result.dart';
import '../../core/secure_store.dart';
import '../../src/rust/api/secrets.dart' show SupabaseConnection;
import '../../src/rust/api/vault.dart' as core;
import '../auth/profile.dart';
import '../groups/group_models.dart';
import '../groups/groups_repository.dart' as groups_repo;
import 'escrow_key.dart';
import 'vault_info.dart';
import 'vault_repository.dart' as repo;

// off：未啟用；loading：確認這台裝置有沒有記住金鑰中；locked：要輸入密碼；unlocked：可以使用
enum VaultStatus { off, loading, locked, unlocked }

/// 設定、更改、停用、重設的結果：error 是失敗原因（成功為 null），note 是成功時的補充說明
class VaultResult {
  const VaultResult.ok([this.note]) : error = null;
  const VaultResult.fail(String this.error) : note = null;

  final String? error;
  final String? note;

  bool get ok => error == null;
}

/*
 * 加密群組的狀態（同網站 VaultProvider）：解鎖、設定／更改／停用加密密碼、忘記密碼重設、開關群組加密。
 * 金鑰的推導（PBKDF2 60 萬次）、驗證與解開的金鑰都在 Rust 安全核心（rust/core/src/vault.rs），Dart 拿不到金鑰；
 * 勾選「在這台裝置記住」時，Rust 用這台裝置的金鑰把它包起來，Dart 只把包過的密文存進系統的安全儲存。
 * 存的時候連同 vault.check 一起存，別的裝置改過密碼就不再使用。
 * 設定、更改、停用時要重新加密的金鑰由 Rust 直接連 Supabase 取得、轉換、寫回（rust/api/src/api/vault.rs），也不經過 Dart。
 * 這些操作成功後，呼叫端要重新讀取 profile 與群組；這裡先換上新的設定，重新讀到 profile 時就不會被當成別的裝置改過而鎖住。
 * 設定或更改密碼時，連同用團隊公鑰封起來的備援密文（escrow_key.dart）一起存；用密碼解鎖成功後，伺服器說缺少就補存（失敗不影響解鎖）。
 * 從伺服器讀回的設定版本不是 1、或 PBKDF2 次數不在 600,000～5,000,000 時不推導金鑰。
 */
class VaultController extends ChangeNotifier {
  VaultStatus status = VaultStatus.off;

  // 設定、更改、停用、重設或開關群組加密成功後，重新讀取 profile（在 main.dart 接到 AuthController.refreshProfile）；
  // 沒有接時設定頁改用 AuthController.loadProfile
  Future<void> Function()? onProfileChanged;

  // 每次解鎖換一個新的編號（鎖定時是 null）：金鑰在 Rust，畫面用這個判斷要不要重新建立驗證碼清單
  int? keyId;
  int _nextKeyId = 0;

  String? _uid;
  VaultInfo? _info;
  // 每次切換使用者或設定都遞增，舊的非同步結果就不算數
  int _generation = 0;

  static String _storeKey(String uid) => 'vault-key:$uid';

  /// 登入或重新讀取 profile 時呼叫
  void attach(Profile profile) {
    final info = profile.vault;
    // 同一個使用者、同一組設定（重新讀取 profile）就維持目前的解鎖狀態
    if (_uid == profile.uid && _info?.check == info?.check) return;
    _uid = profile.uid;
    _info = info;
    _forgetKey();
    final generation = ++_generation;
    status = info == null ? VaultStatus.off : VaultStatus.loading;
    notifyListeners();
    if (info != null) unawaited(_loadDeviceKey(profile.uid, info, generation));
  }

  /// 登出：忘記這台裝置記住的金鑰
  Future<void> detach(String? uid) async {
    _generation++;
    _uid = null;
    _info = null;
    _forgetKey();
    status = VaultStatus.off;
    notifyListeners();
    if (uid != null) await _deleteDeviceKey(uid);
  }

  // Rust 端的金鑰歸零（加密群組的驗證碼金鑰一起清掉）
  void _forgetKey() {
    keyId = null;
    core.vaultLock();
  }

  void _adoptKey() {
    keyId = ++_nextKeyId;
    status = VaultStatus.unlocked;
  }

  Future<void> _loadDeviceKey(String uid, VaultInfo info, int generation) async {
    var restored = false;
    var legacy = false;
    try {
      final raw = await secureStore.read(key: _storeKey(uid));
      if (raw != null) {
        final json = jsonDecode(raw) as Map<String, dynamic>;
        if (json['check'] == info.check) {
          final wrapped = json['wrapped'];
          final key = json['key'];
          if (generation != _generation) return;
          if (wrapped is String) {
            restored = core.vaultRestoreWrapped(check: info.check, wrapped: wrapped);
          } else if (key is String) {
            // 改用 Rust 之前直接存的金鑰：交給 Rust 後改存成包過的格式
            restored = core.vaultRestoreLegacy(check: info.check, keyBase64: key);
            legacy = true;
          }
        }
      }
    } catch (_) {
      restored = false;
    }
    if (generation != _generation) {
      if (restored) core.vaultLock();
      return;
    }
    if (restored) {
      _adoptKey();
      if (legacy) await _saveDeviceKey(uid, info);
    } else {
      status = VaultStatus.locked;
    }
    notifyListeners();
  }

  /// 用密碼解鎖；回傳錯誤訊息，成功為 null
  Future<String?> unlock(String passphrase, {required bool remember}) async {
    final uid = _uid;
    final info = _info;
    if (uid == null || info == null) return '尚未啟用加密';
    if (!isSupportedVault(info)) return unsupportedVaultMessage;
    final generation = _generation;
    final result = await core.vaultUnlock(salt: info.salt, iterations: info.iterations, check: info.check, passphrase: passphrase);
    if (generation != _generation) {
      // 解鎖到一半換了使用者或設定：解開的金鑰不能留著
      if (result == core.VaultUnlockResult.unlocked) core.vaultLock();
      return null;
    }
    switch (result) {
      case core.VaultUnlockResult.badInfo:
        return '加密設定的格式不正確，請用「忘記密碼」重設';
      case core.VaultUnlockResult.unsupported:
        return unsupportedVaultMessage;
      case core.VaultUnlockResult.wrongPassphrase:
        return '密碼錯誤';
      case core.VaultUnlockResult.unlocked:
        break;
    }

    if (remember) {
      await _saveDeviceKey(uid, info);
    } else {
      await _deleteDeviceKey(uid);
    }
    _adoptKey();
    notifyListeners();
    unawaited(_backfillEscrow(uid, info, passphrase, generation));
    return null;
  }

  // 解鎖成功後：伺服器還沒有這組密碼的備援就補上；任何失敗都安靜略過，不影響解鎖
  Future<void> _backfillEscrow(String uid, VaultInfo info, String passphrase, int generation) async {
    try {
      final needed = await repo.escrowNeeded();
      if (needed.dataOrNull != true || generation != _generation || _info?.check != info.check) return;
      final escrow = sealEscrow(uid, passphrase);
      if (escrow == null) return;
      await repo.escrowPut(escrow);
    } catch (error) {
      debugPrint('補存加密密碼備援失敗：$error');
    }
  }

  // 存的是用這台裝置的金鑰包過的密文，不是金鑰本身
  Future<void> _saveDeviceKey(String uid, VaultInfo info) async {
    final wrapped = core.vaultExportWrapped();
    if (wrapped == null) return;
    try {
      await secureStore.write(key: _storeKey(uid), value: jsonEncode({'check': info.check, 'wrapped': wrapped}));
    } catch (_) {
      // 存不了就只在這次有效
    }
  }

  /// 立即鎖定，並忘記這台裝置記住的金鑰
  Future<void> lock() async {
    final uid = _uid;
    if (uid == null || _info == null) return;
    _forgetKey();
    status = VaultStatus.locked;
    notifyListeners();
    await _deleteDeviceKey(uid);
  }

  Future<void> _deleteDeviceKey(String uid) async {
    try {
      await secureStore.delete(key: _storeKey(uid));
    } catch (_) {
      // 沒有存就沒有東西要刪
    }
  }

  // ---------- 設定、更改、停用、重設 ----------

  // 換上新的加密設定（null 是停用）：舊的非同步結果不算數；有新金鑰時已經在 Rust 生效
  void _replaceInfo(VaultInfo? info) {
    _generation++;
    _info = info;
    if (info == null) {
      _forgetKey();
      status = VaultStatus.off;
    } else {
      _adoptKey();
    }
    notifyListeners();
  }

  static VaultInfo _infoOf(core.VaultSetup setup) =>
      VaultInfo(v: 1, salt: setup.salt, iterations: setup.iterations, check: setup.check);

  /// 設定加密密碼；預設群組只有自己一個成員時順便開啟它的加密（同網站 enable）
  Future<VaultResult> enable(String passphrase, {required bool remember}) async {
    final uid = _uid;
    if (uid == null) return const VaultResult.fail('尚未登入');
    final expected = _info?.check;
    final generation = _generation;
    final SupabaseConnection conn;
    switch (await repo.vaultConnection()) {
      case Ok(:final data):
        conn = data;
      case Err(:final message):
        return VaultResult.fail(message);
    }

    final setup = await core.vaultCreate(passphrase: passphrase);
    // 還沒有加密的群組，只需要存加密設定（連同備援密文）
    final error = await core.vaultRewriteAll(
      connection: conn,
      usePending: true,
      expectedCheck: expected,
      escrow: sealEscrow(uid, passphrase),
    );
    if (generation != _generation) return _superseded();
    if (error != null) return VaultResult.fail(error);

    final info = _infoOf(setup);
    _replaceInfo(info);
    if (remember) {
      await _saveDeviceKey(uid, info);
    } else {
      await _deleteDeviceKey(uid);
    }
    return VaultResult.ok(await _encryptHomeGroup(conn, info.check));
  }

  // 預設群組：只有自己一個成員就加密，有其他成員就說明要先移除
  Future<String?> _encryptHomeGroup(SupabaseConnection connection, String check) async {
    final groups = await groups_repo.loadMyGroupsRaw();
    final home = groups.dataOrNull?.map(GroupSummary.fromJson).where((g) => g.isDefault && g.isOwner).firstOrNull;
    if (home == null || home.encrypted) return null;
    if (home.memberCount > 1) return '「${home.name}」還有其他成員，沒有加密；移除成員後可以在群組設定開啟';
    final error = await core.vaultSetGroupEncrypted(connection: connection, gid: home.id, encrypted: true, expectedCheck: check);
    return error == null ? '已加密「${home.name}」' : '加密「${home.name}」失敗：$error';
  }

  /// 更改密碼：用目前的密碼解開，再用新密碼重新加密全部加密群組的金鑰
  Future<VaultResult> changePassphrase(String currentPassphrase, String nextPassphrase) async {
    final uid = _uid;
    final info = _info;
    if (uid == null || info == null) return const VaultResult.fail('尚未啟用加密');
    final generation = _generation;
    final SupabaseConnection conn;
    switch (await repo.vaultConnection()) {
      case Ok(:final data):
        conn = data;
      case Err(:final message):
        return VaultResult.fail(message);
    }

    final setup = await core.vaultCreate(passphrase: nextPassphrase);
    final error = await core.vaultRewriteAll(
      connection: conn,
      current: _current(info, currentPassphrase),
      usePending: true,
      expectedCheck: info.check,
      escrow: sealEscrow(uid, nextPassphrase),
    );
    if (generation != _generation) return _superseded();
    if (error != null) return VaultResult.fail(error);

    // 原本有記住就改記新的金鑰
    final remembered = await _hasDeviceKey(uid);
    final next = _infoOf(setup);
    _replaceInfo(next);
    if (remembered) await _saveDeviceKey(uid, next);
    return const VaultResult.ok();
  }

  /// 停用加密：全部加密群組的金鑰改回明文，群組改成沒加密
  Future<VaultResult> disable(String passphrase) async {
    final uid = _uid;
    final info = _info;
    if (uid == null || info == null) return const VaultResult.fail('尚未啟用加密');
    final generation = _generation;
    final SupabaseConnection conn;
    switch (await repo.vaultConnection()) {
      case Ok(:final data):
        conn = data;
      case Err(:final message):
        return VaultResult.fail(message);
    }

    final error = await core.vaultRewriteAll(
      connection: conn,
      current: _current(info, passphrase),
      usePending: false,
      expectedCheck: info.check,
    );
    if (generation != _generation) return const VaultResult.fail('帳號已變更，請重新操作');
    if (error != null) return VaultResult.fail(error);
    _replaceInfo(null);
    await _deleteDeviceKey(uid);
    return const VaultResult.ok();
  }

  /// 忘記密碼：清空全部加密群組裡的驗證碼並停用加密（不需要密碼）
  Future<VaultResult> reset() async {
    final uid = _uid;
    if (uid == null) return const VaultResult.fail('尚未登入');
    final result = await repo.resetVault();
    if (result case Err(:final message)) return VaultResult.fail(message);
    if (_uid != uid) return const VaultResult.ok();
    _replaceInfo(null);
    await _deleteDeviceKey(uid);
    return const VaultResult.ok();
  }

  /// 開關一個群組的加密：要先設定密碼並解鎖（同網站 setGroupEncryption）；成功回傳 null
  Future<String?> setGroupEncrypted(String gid, bool encrypted) async {
    final info = _info;
    if (info == null) return '請先到「設定」的「加密」設定加密密碼';
    if (status != VaultStatus.unlocked) return '請先輸入加密密碼解鎖';
    final SupabaseConnection conn;
    switch (await repo.vaultConnection()) {
      case Ok(:final data):
        conn = data;
      case Err(:final message):
        return message;
    }
    return core.vaultSetGroupEncrypted(
      connection: conn,
      gid: gid,
      encrypted: encrypted,
      expectedCheck: info.check,
    );
  }

  // 操作到一半登出或換了帳號：Rust 裡剛換上的新金鑰不能留給別人
  VaultResult _superseded() {
    if (status != VaultStatus.unlocked) core.vaultLock();
    return const VaultResult.fail('帳號已變更，請重新操作');
  }

  static core.VaultCurrent _current(VaultInfo info, String passphrase) =>
      core.VaultCurrent(salt: info.salt, iterations: info.iterations, check: info.check, passphrase: passphrase);

  Future<bool> _hasDeviceKey(String uid) async {
    try {
      return await secureStore.read(key: _storeKey(uid)) != null;
    } catch (_) {
      return false;
    }
  }
}

/// 讀回的加密設定異常（版本不對、次數不在範圍）時的訊息
const unsupportedVaultMessage = '加密設定異常，請聯絡我們';

/// 只接受 v = 1、PBKDF2 次數 600,000～5,000,000（同資料庫 totp_set_vault 的檢查）；不合就不推導金鑰
bool isSupportedVault(VaultInfo info) => info.v == 1 && info.iterations >= 600000 && info.iterations <= 5000000;

/// 用團隊公鑰把加密密碼封成備援密文（esc:v1）；設定有問題時回傳 null（不擋住設定密碼，之後解鎖時再補）
String? sealEscrow(String uid, String passphrase) {
  try {
    return core.escrowSeal(publicKey: EscrowKey.publicKey, keyId: EscrowKey.keyId, userId: uid, passphrase: passphrase);
  } catch (error) {
    debugPrint('產生加密密碼備援失敗：$error');
    return null;
  }
}
