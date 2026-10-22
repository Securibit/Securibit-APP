import 'dart:async';
import 'dart:io' show Platform;
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/result.dart';
import '../../core/rpc.dart';
import 'profile_repository.dart' as repo;
import 'session_models.dart';

/// 這台裝置的資料（寫進 session_devices）
typedef DeviceInfo = ({String name, String platform, String appVersion});

/*
 * 回報「這個 session 是哪台裝置」：auth.sessions 的 user_agent 是 Dart 預設值，認不出是哪台，
 * 所以開 App（還原 session）、登入、換 token 時把裝置名稱、平台與 App 版本寫進 session_devices，
 * 網站與 App 的「已登入的裝置」才看得出來。失敗（離線、資料庫還沒執行 0019）就算了，下次再寫。
 *
 * 裝置名稱：Android 是系統設定裡的裝置名稱或「廠牌 型號」（原生端，channel：securibit/device）；
 * iPhone / iPad 拿不到使用者取的名稱，用 iPhone 或 iPad 代替；桌面用電腦的主機名稱。
 */
class SessionDeviceReporter {
  SessionDeviceReporter._();

  static const _channel = MethodChannel('securibit/device');
  // 同一個 session 短時間內只寫一次（開 App 時 initialSession 與 tokenRefreshed 可能連著來）
  static const _interval = Duration(minutes: 10);

  static StreamSubscription<AuthState>? _subscription;
  static DeviceInfo? _device;
  static String? _lastSession;
  static DateTime? _lastAt;

  static void start() {
    _subscription ??= supabase.auth.onAuthStateChange.listen(
      (state) {
        final session = state.session;
        if (session == null) {
          _lastSession = null;
          return;
        }
        final report = switch (state.event) {
          AuthChangeEvent.initialSession || AuthChangeEvent.signedIn || AuthChangeEvent.tokenRefreshed => true,
          _ => false,
        };
        // 過期的 token 寫不進去，等換完 token（tokenRefreshed）再寫
        if (report && !session.isExpired) unawaited(_report(session));
      },
      // 登入流程的錯誤由 AuthController 處理
      onError: (Object _) {},
    );
  }

  /// 馬上回報目前的 session（打開「已登入的裝置」時）；10 分鐘內寫過就不再寫
  static Future<void> reportNow() async {
    final session = supabase.auth.currentSession;
    if (session == null || session.isExpired) return;
    await _report(session);
  }

  static Future<void> _report(Session session) async {
    final sessionId = sessionIdOf(session.accessToken);
    if (sessionId == null) return;
    final now = DateTime.now();
    if (_lastSession == sessionId && _lastAt != null && now.difference(_lastAt!) < _interval) return;
    _lastSession = sessionId;
    _lastAt = now;

    final device = _device ??= await _deviceInfo();
    final result = await repo.saveSessionDevice(
      sessionId: sessionId,
      userId: session.user.id,
      deviceName: device.name,
      platform: device.platform,
      appVersion: device.appVersion,
    );
    // 沒寫成功就讓下一次事件再試
    if (result is Err<void> && _lastSession == sessionId) _lastSession = null;
  }

  static Future<DeviceInfo> _deviceInfo() async {
    String appVersion = '';
    try {
      appVersion = (await PackageInfo.fromPlatform()).version;
    } catch (_) {
      // 讀不到版本就不寫
    }
    return (name: await _deviceName(), platform: Platform.operatingSystem, appVersion: appVersion);
  }

  static Future<String> _deviceName() async {
    if (Platform.isAndroid) {
      try {
        final name = await _channel.invokeMethod<String>('name');
        if (name != null && name.trim().isNotEmpty) return name.trim();
      } on MissingPluginException {
        // 測試環境沒有原生端
      } on PlatformException {
        // 讀不到就用平台名稱
      }
      return 'Android 裝置';
    }
    if (Platform.isIOS) return _isTablet ? 'iPad' : 'iPhone';
    try {
      final name = cleanHostname(Platform.localHostname);
      if (name != null) return name;
    } catch (_) {
      // 讀不到主機名稱就用平台名稱
    }
    if (Platform.isMacOS) return 'Mac';
    if (Platform.isWindows) return 'Windows 電腦';
    return 'Linux 電腦';
  }

  // 短邊 600 以上當成平板（同 Flutter 常用的分法）
  static bool get _isTablet {
    final view = PlatformDispatcher.instance.implicitView;
    if (view == null || view.devicePixelRatio == 0) return false;
    final size = view.physicalSize / view.devicePixelRatio;
    return size.shortestSide >= 600;
  }
}
