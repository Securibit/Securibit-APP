import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../core/secure_store.dart';
import '../../src/rust/api/vault.dart' as core;
import '../auth/profile.dart';
import 'vault_info.dart';

// off：未啟用；loading：確認這台裝置有沒有記住金鑰中；locked：要輸入密碼；unlocked：可以使用
enum VaultStatus { off, loading, locked, unlocked }

/*
 * 加密群組的解鎖狀態（同網站 VaultProvider，但這裡只負責解鎖；設定、更改、停用加密請到網站）。
 * 金鑰的推導（PBKDF2 60 萬次）、驗證與解開的金鑰都在 Rust 安全核心（rust/core/src/vault.rs），Dart 拿不到金鑰；
 * 勾選「在這台裝置記住」時，Rust 用這台裝置的金鑰把它包起來，Dart 只把包過的密文存進系統的安全儲存。
 * 存的時候連同 vault.check 一起存，別的裝置改過密碼就不再使用。
 */
class VaultController extends ChangeNotifier {
  VaultStatus status = VaultStatus.off;

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
    final generation = _generation;
    final result = await core.vaultUnlock(salt: info.salt, iterations: info.iterations, check: info.check, passphrase: passphrase);
    if (generation != _generation) {
      // 解鎖到一半換了使用者或設定：解開的金鑰不能留著
      if (result == core.VaultUnlockResult.unlocked) core.vaultLock();
      return null;
    }
    switch (result) {
      case core.VaultUnlockResult.badInfo:
        return '加密設定的格式不正確，請到網站重新設定';
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
    return null;
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
}
