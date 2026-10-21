import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/platform.dart';
import '../../../core/secure_store.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/logo.dart';
import '../../auth/auth_controller.dart';
import '../app_lock.dart';
import 'app_lock_controller.dart';
import 'lock_entry.dart';
import 'lock_wait.dart';

/*
 * 全螢幕的鎖定畫面：蓋住所有內容，輸入圖形或密碼解鎖。
 * 有開生物辨識時一出現就自動跳出 Face ID / 指紋；取消後可以按鍵盤左下角（圖形是下方的按鈕）再試。
 * 「忘記密碼」會登出並清除這台裝置的資料，重新登入後驗證碼從伺服器回來。
 */
class LockScreen extends StatefulWidget {
  const LockScreen({super.key, required this.lock, required this.onUnlocked});

  final AppLockController lock;
  final VoidCallback onUnlocked;

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> with WidgetsBindingObserver, LockWaitTicker {
  String? _message;
  bool _error = false;
  bool _face = false;
  bool _prompting = false;
  bool _resetting = false;
  // 真的離開過 App（不是生物辨識對話框造成的 inactive）回來才再自動跳生物辨識
  bool _wasAway = false;

  @override
  AppLockController get lock => widget.lock;

  bool get _canBiometric => lock.biometric && AppPlatform.canUseBiometrics;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    syncWait();
    if (_canBiometric) {
      biometricIsFace().then((face) {
        if (mounted) setState(() => _face = face);
      });
      // 「立即」鎖定時這個畫面是在背景建立的，等回到前景再跳
      if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _biometric());
      } else {
        _wasAway = true;
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_prompting) return;
    if (state == AppLifecycleState.hidden || state == AppLifecycleState.paused) {
      _wasAway = true;
    } else if (state == AppLifecycleState.resumed && _wasAway) {
      _wasAway = false;
      syncWait();
      if (_canBiometric) _biometric();
    }
  }

  Future<void> _biometric() async {
    if (_prompting || _resetting || !mounted) return;
    _prompting = true;
    final error = await authenticateOwner();
    _prompting = false;
    if (!mounted) return;
    if (error == null) {
      await lock.resetAttempts();
      if (mounted) widget.onUnlocked();
      return;
    }
    // 使用者自己取消就不顯示錯誤
    if (error != biometricRejected) {
      setState(() {
        _message = error;
        _error = true;
      });
    }
  }

  Future<bool> _check(String secret) async {
    final result = await lock.verify(secret);
    if (!mounted) return false;
    if (result is LockCheckOk) {
      widget.onUnlocked();
      return true;
    }
    syncWait();
    setState(() {
      _message = waiting ? null : lockCheckMessage(result, lock.type, DateTime.now());
      _error = true;
    });
    return false;
  }

  Future<void> _forgot() async {
    final ok = await confirmDialog(
      context,
      title: '忘記${lockNoun(lock.type)}',
      message: '會登出 Securibit，並清除這台裝置上的登入狀態、離線資料、記住的加密群組密碼與鎖定設定\n\n'
          '驗證碼都存在伺服器上，重新登入後就會回來；加密群組要再輸入一次加密密碼',
      confirmLabel: '登出並清除',
      danger: true,
    );
    if (!ok || !mounted) return;
    setState(() => _resetting = true);
    final auth = context.read<AuthController>();
    // 連不上伺服器也會先清掉本機的 session
    await auth.signOut();
    await lock.wipe();
    try {
      await secureStore.deleteAll();
    } catch (_) {
      // 安全儲存無法使用時本來就沒有存東西
    }
    if (!mounted) return;
    widget.onUnlocked();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = lock.type;
    final biometricLabel = _face ? '使用 Face ID' : (AppPlatform.isMobile ? '使用指紋' : '使用 Touch ID');
    final biometricIcon = Icon(_face ? Icons.face_rounded : Icons.fingerprint_rounded, size: 34);
    final waitText = waitMessage;

    return Scaffold(
      backgroundColor: colors.surface,
      body: SafeArea(
        child: Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const AppLogo(size: 52),
                  const SizedBox(height: 20),
                  LockEntry(
                    type: type,
                    title: type.isPin ? '輸入密碼' : '畫出解鎖圖形',
                    message: waitText ?? _message,
                    error: waitText != null || _error,
                    enabled: waitText == null && !_resetting,
                    onSubmit: _check,
                    keypadAction: _canBiometric
                        ? IconButton(
                            tooltip: biometricLabel,
                            onPressed: _resetting ? null : _biometric,
                            color: colors.accent,
                            icon: biometricIcon,
                          )
                        : null,
                  ),
                  const SizedBox(height: 16),
                  if (_canBiometric && !type.isPin)
                    TextButton.icon(
                      onPressed: _resetting ? null : _biometric,
                      icon: Icon(_face ? Icons.face_rounded : Icons.fingerprint_rounded),
                      label: Text(biometricLabel),
                    ),
                  TextButton(
                    onPressed: _resetting ? null : _forgot,
                    style: TextButton.styleFrom(foregroundColor: colors.inkMuted),
                    child: Text('忘記${lockNoun(type)}'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
