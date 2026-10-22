import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/*
 * 系統的安全儲存（Keychain / Keystore / libsecret / Windows 的 DPAPI）。
 * macOS 用傳統的登入鑰匙圈（useDataProtectionKeyChain: false），
 * 不需要 keychain-access-groups 權限，沒有簽署開發者憑證的 debug 版也能用。
 *
 * Windows（flutter_secure_storage_windows 3.x）不用認證管理員（每筆上限 2560 bytes，放不下離線快取），
 * 而是把全部的項目合成一份 JSON，用 DPAPI（CryptProtectData，綁這個 Windows 使用者）加密後存成
 * %APPDATA%\BITYO\Securibit\flutter_secure_storage.dat，沒有大小限制。
 * 不讀舊版放在認證管理員的資料（useBackwardCompatibility: false）：Windows 版一開始就是新的格式，
 * 打開的話每次讀不到的 key 都會再去查一次認證管理員。
 * 每次寫入都是「讀出整份 → 改一筆 → 寫回整份」，同時寫兩筆時後寫完的會蓋掉先寫的
 * （例如登入時 session 和離線快取一起存），所以 Windows 上所有讀寫排隊一筆一筆做。
 */
final secureStore = SecureStore(
  const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
    mOptions: MacOsOptions(useDataProtectionKeyChain: false, accessibility: KeychainAccessibility.first_unlock_this_device),
    wOptions: WindowsOptions(useBackwardCompatibility: false),
  ),
  serial: Platform.isWindows,
);

/// FlutterSecureStorage 加上 Windows 的排隊；只包 App 用到的方法
class SecureStore {
  /// App 用上面的 secureStore；測試可以換成假的 storage
  SecureStore(this._storage, {required bool serial}) : _serial = serial;

  final FlutterSecureStorage _storage;
  final bool _serial;
  // 排在最後的一筆；前一筆失敗也照樣做下一筆
  Future<void> _tail = Future.value();

  MacOsOptions get mOptions => _storage.mOptions;
  WindowsOptions get wOptions => _storage.wOptions;

  Future<T> _run<T>(Future<T> Function() run) {
    if (!_serial) return run();
    final result = _tail.then((_) => run());
    _tail = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  Future<String?> read({required String key}) => _run(() => _storage.read(key: key));

  Future<void> write({required String key, required String? value}) => _run(() => _storage.write(key: key, value: value));

  Future<void> delete({required String key}) => _run(() => _storage.delete(key: key));

  Future<bool> containsKey({required String key}) => _run(() => _storage.containsKey(key: key));

  Future<Map<String, String>> readAll() => _run(_storage.readAll);

  Future<void> deleteAll() => _run(_storage.deleteAll);
}
