import 'dart:async';

import '../../../core/result.dart';
import '../../../core/rpc.dart';
import '../../profile/session_device.dart';
import '../../profile/session_models.dart';
import '../notifications_repository.dart' as repo;
import 'android_push.dart';

/*
 * 把這台 Android 的推播 token 寫進目前這個 session（register_push_token，只寫自己 session 那一列）：
 * - session 的裝置資料寫好時（登入、開 App、換 token；見 SessionDeviceReporter.reported）
 * - FCM 換了 token 時
 * 同一個 session、同一個 token 只寫一次；失敗就等下一次事件再試。
 * 登出前（AuthController.beforeSignOut）送 null 清掉；session 刪掉時資料庫也會一起清掉。
 * 沒有 google-services.json（Push 不能用）時什麼都不做。
 */
class PushRegistrar {
  PushRegistrar._();

  static String? _token;
  static (String, String)? _registered;
  static bool _started = false;
  static bool? _available;

  static void start() {
    if (!AndroidPush.supported || _started) return;
    _started = true;
    AndroidPush.listen();
    SessionDeviceReporter.reported.listen((_) => unawaited(_sync()));
    AndroidPush.tokenChanges.listen((token) {
      _token = token;
      unawaited(_sync());
    });
  }

  static Future<bool> _isAvailable() async => _available ??= await AndroidPush.available();

  static Future<void> _sync() async {
    if (!await _isAvailable()) return;
    final session = supabase.auth.currentSession;
    if (session == null || session.isExpired) return;
    final sessionId = sessionIdOf(session.accessToken);
    if (sessionId == null) return;
    final token = _token ??= await AndroidPush.token();
    if (token == null || token.isEmpty) return;
    if (_registered == (sessionId, token)) return;
    final result = await repo.registerPushToken(token);
    if (result is Ok<void>) _registered = (sessionId, token);
  }

  /// 登出前：這個 session 不再收推播
  static Future<void> unregister() async {
    if (!AndroidPush.supported || !await _isAvailable()) return;
    _registered = null;
    await repo.registerPushToken(null);
  }
}
