import 'dart:async';
import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';

import '../../core/secure_store.dart';
import '../auth/profile.dart';
import 'vault_crypto.dart';
import 'vault_info.dart';

// off：未啟用；loading：確認這台裝置有沒有記住金鑰中；locked：要輸入密碼；unlocked：可以使用
enum VaultStatus { off, loading, locked, unlocked }

/*
 * 加密群組的解鎖狀態（同網站 VaultProvider，但這裡只負責解鎖；設定、更改、停用加密請到網站）。
 * 解開的金鑰只在記憶體；勾選「在這台裝置記住」才存進系統的安全儲存（Keychain / Keystore）。
 * 存的時候連同 vault.check 一起存，別的裝置改過密碼就不再使用。
 */
class VaultController extends ChangeNotifier {
  VaultStatus status = VaultStatus.off;
  SecretKey? key;

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
    key = null;
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
    key = null;
    status = VaultStatus.off;
    notifyListeners();
    if (uid != null) await _deleteDeviceKey(uid);
  }

  Future<void> _loadDeviceKey(String uid, VaultInfo info, int generation) async {
    SecretKey? stored;
    try {
      final raw = await secureStore.read(key: _storeKey(uid));
      if (raw != null) {
        final json = jsonDecode(raw) as Map<String, dynamic>;
        if (json['check'] == info.check) {
          final candidate = SecretKey(base64.decode(json['key'] as String));
          if (await verifyVaultKey(info, candidate)) stored = candidate;
        }
      }
    } catch (_) {
      stored = null;
    }
    if (generation != _generation) return;
    key = stored;
    status = stored == null ? VaultStatus.locked : VaultStatus.unlocked;
    notifyListeners();
  }

  /// 用密碼解鎖；回傳錯誤訊息，成功為 null
  Future<String?> unlock(String passphrase, {required bool remember}) async {
    final uid = _uid;
    final info = _info;
    if (uid == null || info == null) return '尚未啟用加密';
    final generation = _generation;
    final SecretKey? unlocked;
    try {
      unlocked = await unlockVault(info, passphrase);
    } catch (_) {
      return '加密設定的格式不正確，請到網站重新設定';
    }
    if (generation != _generation) return null;
    if (unlocked == null) return '密碼錯誤';

    if (remember) {
      try {
        final bytes = await unlocked.extractBytes();
        await secureStore.write(key: _storeKey(uid), value: jsonEncode({'check': info.check, 'key': base64.encode(bytes)}));
      } catch (_) {
        // 存不了就只在這次有效
      }
    } else {
      await _deleteDeviceKey(uid);
    }
    key = unlocked;
    status = VaultStatus.unlocked;
    notifyListeners();
    return null;
  }

  /// 立即鎖定，並忘記這台裝置記住的金鑰
  Future<void> lock() async {
    final uid = _uid;
    if (uid == null || _info == null) return;
    key = null;
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
