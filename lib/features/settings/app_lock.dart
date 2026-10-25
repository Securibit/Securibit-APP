import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/error_codes.dart' as auth_error;
import 'package:local_auth/local_auth.dart';
import 'package:provider/provider.dart';

import '../../core/platform.dart';
import '../../core/security_core.dart';
import '../../core/window_visibility.dart';
import '../auth/auth_controller.dart';
import 'lock/app_lock_controller.dart';
import 'lock/lock_policy.dart';
import 'lock/lock_screen.dart';
import 'settings_controller.dart';

final _localAuth = LocalAuthentication();

// 生物辨識的對話框也會讓 App 進入 inactive / hidden，跳出來的期間鎖定畫面不要把它當成離開 App
bool _biometricPromptActive = false;

/// 設定頁的開關文字，依平台寫實際能用的方式
String get biometricUnlockLabel {
  if (Platform.isIOS) return '也可用 Face ID／Touch ID 解鎖';
  if (Platform.isMacOS) return '也可用 Touch ID 解鎖';
  return '也可用指紋或臉部解鎖';
}

/// 這台裝置的生物辨識是不是臉部（決定鎖定畫面的圖示與文字）
Future<bool> biometricIsFace() async {
  if (!AppPlatform.canUseBiometrics) return false;
  try {
    final types = await _localAuth.getAvailableBiometrics();
    return types.contains(BiometricType.face) && !types.contains(BiometricType.fingerprint);
  } on PlatformException {
    return false;
  }
}

/// 鎖定畫面自己的 Navigator：鎖著時要跳出的提示（例如新版本）開在這裡，才不會被鎖定畫面蓋住
final lockNavigatorKey = GlobalKey<NavigatorState>();

/// 跳出提示用的 context：鎖著時是鎖定畫面，否則是 App 的畫面
BuildContext? promptContext(GlobalKey<NavigatorState> appNavigator) => lockNavigatorKey.currentContext ?? appNavigator.currentContext;

// 使用者取消或沒有通過時的訊息（鎖定畫面不顯示）
const biometricRejected = '沒有通過驗證';

/// 用 Face ID / Touch ID / 指紋驗證本人；只接受生物辨識，不接受裝置密碼（圖形或密碼才是備用方式）
/// 回傳錯誤訊息，成功為 null
Future<String?> authenticateOwner() async {
  if (!AppPlatform.canUseBiometrics) return '這個平台不支援生物辨識';
  _biometricPromptActive = true;
  try {
    if (!await _localAuth.isDeviceSupported()) return '這台裝置不支援生物辨識';
    final ok = await _localAuth.authenticate(
      localizedReason: '解鎖 Securibit',
      options: const AuthenticationOptions(stickyAuth: true, biometricOnly: true),
    );
    return ok ? null : biometricRejected;
  } on PlatformException catch (error) {
    return switch (error.code) {
      auth_error.notEnrolled => '這台裝置還沒有設定 Face ID、Touch ID 或指紋',
      auth_error.notAvailable || auth_error.biometricOnlyNotSupported => '這台裝置無法使用生物辨識',
      auth_error.passcodeNotSet => '這台裝置還沒有設定螢幕密碼',
      auth_error.lockedOut => '生物辨識錯誤太多次，請稍後再試',
      auth_error.permanentlyLockedOut => '生物辨識已停用，請先用裝置密碼解鎖',
      _ => error.message ?? '無法使用生物辨識',
    };
  } finally {
    _biometricPromptActive = false;
  }
}

/*
 * App 鎖定：設定圖形或密碼後，打開 App 時、以及離開 App 超過設定的時間再回來時要先解鎖。
 * 包在 MaterialApp.builder，連設定頁、對話框等推上去的畫面一起蓋住；
 * 鎖定時下面的畫面不繪製（Offstage），看不到內容但狀態保留，解鎖後回到原本的畫面。
 * 桌面視窗只是失去焦點不會鎖，最小化、切到背景或（macOS 選單列常駐時）關掉視窗才算離開。
 * 沒有登入時沒有資料要保護，不顯示鎖定畫面。
 * 鎖定時同時封存 Rust 記憶體裡的金鑰（全部歸零），解鎖後各個畫面再從離線快取的密文放回來；
 * 桌面視窗藏起來（例如 macOS 選單列常駐）時，過了自動鎖定時間就先鎖，不用等視窗重新顯示。
 */
class AppLockGate extends StatefulWidget {
  const AppLockGate({super.key, required this.child});

  final Widget child;

  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends State<AppLockGate> with WidgetsBindingObserver {
  late final AppLockController _lock = context.read<SettingsController>().appLock;
  // 冷啟動一定要解鎖
  late bool _locked = _lock.enabled;

  // 視窗藏著時，到了自動鎖定時間就鎖
  Timer? _autoLock;

  @override
  void initState() {
    super.initState();
    _setLocked(_locked);
    _lock.leftAt = null;
    WidgetsBinding.instance.addObserver(this);
    WindowVisibility.visible.addListener(_onWindowVisibility);
    _lock.addListener(_onLockChanged);
  }

  @override
  void dispose() {
    _autoLock?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    WindowVisibility.visible.removeListener(_onWindowVisibility);
    _lock.removeListener(_onLockChanged);
    super.dispose();
  }

  // 鎖定狀態同步給 AppLockController（選單列／系統匣看它決定能不能列出驗證碼）
  void _setLocked(bool value) {
    _locked = value;
    _lock.screenLocked = value;
    if (value) _autoLock?.cancel();
    // 鎖定：Rust 清掉全部金鑰；解鎖：讓各個畫面把金鑰放回來
    if (value != SecretSeal.sealed.value) value ? SecretSeal.seal() : SecretSeal.unseal();
  }

  // 關閉鎖定或忘記密碼之後就不再鎖著
  void _onLockChanged() {
    if (!_lock.enabled && _locked) setState(() => _setLocked(false));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.hidden || state == AppLifecycleState.paused) {
      _leave();
    } else if (state == AppLifecycleState.resumed) {
      // 選單列／系統匣常駐時，視窗藏著也可能收到 resumed（例如從選單列複製），視窗顯示時才算回來
      if (WindowVisibility.visible.value) _return();
    }
  }

  // 選單列／系統匣常駐：主視窗藏起來算離開 App，重新顯示算回來
  void _onWindowVisibility() => WindowVisibility.visible.value ? _return() : _leave();

  void _leave() {
    if (!_lock.enabled || _biometricPromptActive) return;
    _lock.leftAt ??= DateTime.now();
    // 「立即」在離開時就鎖，回來的第一個畫面就是鎖定畫面
    if (_lock.timeout == LockTimeout.immediate) {
      _lockNow();
    } else {
      _autoLock?.cancel();
      _autoLock = Timer(_lock.timeout.duration, _lockNow);
    }
  }

  void _return() {
    if (!_lock.enabled || _biometricPromptActive) return;
    _autoLock?.cancel();
    final at = _lock.leftAt;
    _lock.leftAt = null;
    if (shouldLockAfterBackground(backgroundedAt: at, now: DateTime.now(), timeout: _lock.timeout)) _lockNow();
  }

  void _lockNow() {
    if (_locked || !mounted || !_lock.enabled) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _setLocked(true));
  }

  @override
  Widget build(BuildContext context) {
    final signedOut = context.select<AuthController, bool>((auth) => auth.status == AuthStatus.signedOut);
    // 登出後不用再解鎖，剛登入完也不要馬上要求解鎖
    if (signedOut) _setLocked(false);
    final showLock = _locked && _lock.enabled;
    return Stack(
      fit: StackFit.expand,
      children: [
        Offstage(offstage: showLock, child: TickerMode(enabled: !showLock, child: widget.child)),
        if (showLock)
          // 鎖定畫面有自己的 Navigator，「忘記密碼」的確認對話框才跳得出來（不和 App 的 Navigator 共用 HeroController）
          HeroControllerScope.none(
            child: Navigator(
              key: lockNavigatorKey,
              onGenerateRoute: (_) => PageRouteBuilder<void>(
                pageBuilder: (_, _, _) => LockScreen(lock: _lock, onUnlocked: () => setState(() => _setLocked(false))),
              ),
            ),
          ),
      ],
    );
  }
}
