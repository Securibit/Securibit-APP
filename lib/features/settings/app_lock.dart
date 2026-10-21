import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:provider/provider.dart';

import '../../core/platform.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/logo.dart';
import 'settings_controller.dart';

final _localAuth = LocalAuthentication();

/// 用 Face ID / Touch ID / 指紋（或裝置密碼）驗證本人；回傳錯誤訊息，成功為 null
Future<String?> authenticateOwner() async {
  if (!AppPlatform.canUseBiometrics) return '這個平台不支援生物辨識';
  try {
    if (!await _localAuth.isDeviceSupported()) return '這台裝置沒有設定生物辨識或裝置密碼';
    final ok = await _localAuth.authenticate(
      localizedReason: '解鎖 Securibit',
      options: const AuthenticationOptions(stickyAuth: true),
    );
    return ok ? null : '沒有通過驗證';
  } on PlatformException catch (error) {
    return error.message ?? '無法使用生物辨識';
  }
}

/*
 * 生物辨識鎖定：設定開啟後，App 開啟時、以及離開 App 再回來時要先通過驗證。
 * 桌面視窗只是失去焦點不會鎖，最小化或切到背景才會。
 */
class AppLockGate extends StatefulWidget {
  const AppLockGate({super.key, required this.child});

  final Widget child;

  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends State<AppLockGate> with WidgetsBindingObserver {
  late bool _locked = context.read<SettingsController>().biometricLock && AppPlatform.canUseBiometrics;
  bool _authenticating = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (_locked) WidgetsBinding.instance.addPostFrameCallback((_) => _unlock());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final enabled = context.read<SettingsController>().biometricLock && AppPlatform.canUseBiometrics;
    // 驗證對話框本身也會讓 App 進入 inactive / hidden，驗證中不要再鎖
    if (enabled && !_authenticating && (state == AppLifecycleState.hidden || state == AppLifecycleState.paused)) {
      setState(() => _locked = true);
    }
    if (state == AppLifecycleState.resumed && _locked && !_authenticating) _unlock();
  }

  Future<void> _unlock() async {
    if (_authenticating) return;
    setState(() {
      _authenticating = true;
      _error = null;
    });
    final error = await authenticateOwner();
    if (!mounted) return;
    setState(() {
      _authenticating = false;
      _error = error;
      if (error == null) _locked = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_locked) return widget.child;
    final colors = context.colors;
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const AppLogo(size: 64),
              const SizedBox(height: 16),
              const Text('Securibit 已鎖定', style: TextStyle(fontSize: AppText.title, fontWeight: FontWeight.w700)),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, textAlign: TextAlign.center, style: TextStyle(fontSize: AppText.secondary, color: colors.alarm)),
              ],
              const SizedBox(height: 24),
              FilledButton(onPressed: _authenticating ? null : _unlock, child: const Text('解鎖')),
            ],
          ),
        ),
      ),
    );
  }
}
