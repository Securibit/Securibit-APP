import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/secure_store.dart';

/*
 * 把登入 session 存在系統的安全儲存（Keychain / Keystore / libsecret），App 重開後免重新登入。
 * 安全儲存無法使用時（例如 Linux 沒有 Secret Service）改存 SharedPreferences，避免每次都要重新登入。
 */
class SecureSessionStorage extends LocalStorage {
  SecureSessionStorage();

  static const _key = 'securibit-session';
  final _fallback = SharedPreferencesLocalStorage(persistSessionKey: _key);
  bool _useFallback = false;

  @override
  Future<void> initialize() async {
    try {
      await secureStore.containsKey(key: _key);
    } catch (_) {
      _useFallback = true;
      await _fallback.initialize();
    }
  }

  @override
  Future<bool> hasAccessToken() async =>
      _useFallback ? _fallback.hasAccessToken() : await secureStore.containsKey(key: _key);

  @override
  Future<String?> accessToken() async => _useFallback ? _fallback.accessToken() : await secureStore.read(key: _key);

  @override
  Future<void> persistSession(String persistSessionString) async {
    if (_useFallback) return _fallback.persistSession(persistSessionString);
    await secureStore.write(key: _key, value: persistSessionString);
  }

  @override
  Future<void> removePersistedSession() async {
    if (_useFallback) return _fallback.removePersistedSession();
    await secureStore.delete(key: _key);
  }
}
