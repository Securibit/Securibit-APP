import 'dart:async';
import 'dart:io' show Platform;
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show AppLifecycleListener, AppLifecycleState, WidgetsBinding;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/result.dart';
import '../../core/rpc.dart';
import '../../core/security_core.dart';
import '../../core/window_visibility.dart';
import 'profile_repository.dart' as repo;
import 'session_models.dart';

/// 這台裝置的資料（寫進 session_devices）
typedef DeviceInfo = ({String name, String platform, String appVersion});

/*
 * 回報「這個 session 是哪台裝置」：auth.sessions 的 user_agent 是 Dart 預設值，認不出是哪台，
 * 所以開 App（還原 session）、登入、換 token 時把裝置名稱、平台與 App 版本寫進 session_devices，
 * 網站與 App 的「已登入的裝置」才看得出來。失敗（離線、資料庫還沒有這個功能）就算了，下次再寫。
 *
 * last_seen_at 是「最後使用」：App 在畫面上而且沒有鎖定時每 5 分鐘寫一次，離開（縮到背景、關掉視窗、鎖定）時馬上寫一次；
 * 只是常駐在背景換 token 時不更新它（只更新裝置名稱與版本），「已登入的裝置」的最後活動才是真的在用的時間。
 * 直接結束程式、斷線時離開那一下寫不到，靠每 5 分鐘那一筆，最多差 5 分鐘。
 *
 * 裝置名稱：Android 是系統設定裡的裝置名稱或「廠牌 型號」（原生端，channel：securibit/device）；
 * iPhone / iPad 拿不到使用者取的名稱，用 iPhone 或 iPad 代替；桌面用電腦的主機名稱。
 */
class SessionDeviceReporter {
  SessionDeviceReporter._();

  static const _channel = MethodChannel('securibit/device');
  // 使用中每隔多久記一次最後使用；同一個 session 這段時間內也只寫一次（開 App 時 initialSession 與 tokenRefreshed 可能連著來）
  static const _interval = Duration(minutes: 5);

  static StreamSubscription<AuthState>? _subscription;
  static AppLifecycleListener? _lifecycle;
  static Timer? _heartbeat;
  static bool _wasInUse = false;
  static DeviceInfo? _device;
  static String? _lastSession;
  static DateTime? _lastAt;
  static final _reported = StreamController<String>.broadcast();

  /// 寫好了這個 session 的裝置資料（session id）；推播 token 要等這一列存在才寫得進去（見 push_registrar.dart）
  static Stream<String> get reported => _reported.stream;

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
        if (report && !session.isExpired) unawaited(_report(session, used: _inUse));
      },
      // 登入流程的錯誤由 AuthController 處理
      onError: (Object _) {},
    );
    if (_lifecycle == null) {
      _lifecycle = AppLifecycleListener(onStateChange: (_) => _onUsage());
      WindowVisibility.visible.addListener(_onUsage);
      SecretSeal.sealed.addListener(_onUsage);
      _onUsage();
    }
  }

  // 正在使用：App 在前景（桌面是視窗開著，失去焦點也算），而且沒有鎖定
  static bool get _inUse {
    final state = WidgetsBinding.instance.lifecycleState;
    final foreground = state == null || state == AppLifecycleState.resumed || state == AppLifecycleState.inactive;
    return foreground && WindowVisibility.visible.value && !SecretSeal.sealed.value;
  }

  static void _onUsage() {
    final inUse = _inUse;
    if (inUse == _wasInUse) return;
    _wasInUse = inUse;
    _heartbeat?.cancel();
    _heartbeat = null;
    final session = supabase.auth.currentSession;
    if (inUse) {
      _heartbeat = Timer.periodic(_interval, (_) {
        final current = supabase.auth.currentSession;
        if (current != null && !current.isExpired) unawaited(_report(current, used: true, force: true));
      });
    }
    // 開始使用（打開、回到前景、解鎖）與離開的那一刻都記下，不受 5 分鐘只寫一次的限制
    if (session != null && !session.isExpired) unawaited(_report(session, used: true, force: true));
  }

  /// 馬上回報目前的 session（打開「已登入的裝置」時）；5 分鐘內寫過就不再寫
  static Future<void> reportNow() async {
    final session = supabase.auth.currentSession;
    if (session == null || session.isExpired) return;
    await _report(session, used: _inUse);
  }

  // used：一併更新最後使用時間；force：不管 5 分鐘內寫過沒有（定時、開始使用與離開時）
  static Future<void> _report(Session session, {required bool used, bool force = false}) async {
    final sessionId = sessionIdOf(session.accessToken);
    if (sessionId == null) return;
    final now = DateTime.now();
    if (!force && _lastSession == sessionId && _lastAt != null && now.difference(_lastAt!) < _interval) return;
    _lastSession = sessionId;
    _lastAt = now;

    final device = _device ??= await _deviceInfo();
    final result = await repo.saveSessionDevice(
      sessionId: sessionId,
      userId: session.user.id,
      deviceName: device.name,
      platform: device.platform,
      appVersion: device.appVersion,
      used: used,
    );
    // 沒寫成功就讓下一次事件再試
    if (result is Err<void> && _lastSession == sessionId) _lastSession = null;
    if (result is Ok<void>) _reported.add(sessionId);
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
