import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/secure_store.dart';

/*
 * 把登入 session 存在系統的安全儲存（Keychain / Keystore / libsecret），App 重開後免重新登入。
 * 安全儲存無法使用時（例如 Linux 沒有 Secret Service）改存 SharedPreferences，避免每次都要重新登入。
 * Keystore 偶爾暫時失敗（部分 Android 手機）：讀寫失敗時稍等再試。
 * 一定要存到換新後的 session：refresh token 每次換新都會作廢舊的，下次開 App 拿舊的去換，伺服器會撤銷整個 session。
 */
class SecureSessionStorage extends LocalStorage {
  SecureSessionStorage();

  static const _key = 'securibit-session';
  static const _retryDelay = Duration(milliseconds: 300);
  static const _attempts = 3;

  final _fallback = SharedPreferencesLocalStorage(persistSessionKey: _key);
  bool _useFallback = false;
  // 最新一筆要存的 session；重試前已經有更新的（或已登出）就不再寫舊的
  String? _latest;

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
      _useFallback ? _fallback.hasAccessToken() : await _retry(() => secureStore.containsKey(key: _key)) ?? false;

  @override
  Future<String?> accessToken() async =>
      _useFallback ? _fallback.accessToken() : await _retry<String?>(() => secureStore.read(key: _key));

  @override
  Future<void> persistSession(String persistSessionString) async {
    if (_useFallback) return _fallback.persistSession(persistSessionString);
    _latest = persistSessionString;
    await _retry(
      () => secureStore.write(key: _key, value: persistSessionString),
      stillWanted: () => _latest == persistSessionString,
    );
  }

  @override
  Future<void> removePersistedSession() async {
    if (_useFallback) return _fallback.removePersistedSession();
    _latest = null;
    await _retry(() => secureStore.delete(key: _key));
  }

  // 只有 stillWanted 回傳 false（不用再寫了）時才會是 null
  static Future<T?> _retry<T>(Future<T> Function() run, {bool Function()? stillWanted}) async {
    for (var attempt = 1; ; attempt++) {
      try {
        return await run();
      } catch (_) {
        if (attempt >= _attempts) rethrow;
        await Future<void>.delayed(_retryDelay);
        if (stillWanted != null && !stillWanted()) return null;
      }
    }
  }
}
