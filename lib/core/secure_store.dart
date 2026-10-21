import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/*
 * 系統的安全儲存（Keychain / Keystore / libsecret）。
 * macOS 用傳統的登入鑰匙圈（useDataProtectionKeyChain: false），
 * 不需要 keychain-access-groups 權限，沒有簽署開發者憑證的 debug 版也能用。
 */
const secureStore = FlutterSecureStorage(
  aOptions: AndroidOptions(encryptedSharedPreferences: true),
  iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
  mOptions: MacOsOptions(useDataProtectionKeyChain: false, accessibility: KeychainAccessibility.first_unlock_this_device),
);
