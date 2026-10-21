import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'core/theme/app_theme.dart';
import 'core/theme/tokens.dart';
import 'core/widgets/empty_state.dart';
import 'core/widgets/logo.dart';
import 'features/auth/auth_controller.dart';
import 'features/auth/login_page.dart';
import 'features/settings/app_lock.dart';
import 'features/settings/settings_controller.dart';
import 'features/shell/home_shell.dart';

const _locale = Locale('zh', 'TW');

class SecuribitApp extends StatelessWidget {
  const SecuribitApp({super.key, required this.home});

  final Widget home;

  @override
  Widget build(BuildContext context) {
    final themeMode = context.select<SettingsController, ThemeMode>((s) => s.themeMode);
    return MaterialApp(
      title: 'Securibit',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: themeMode,
      // 繁體中文：系統元件（複製、貼上…）的文字與中文字型都用台灣的
      locale: _locale,
      supportedLocales: const [_locale],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      // App 鎖定蓋在 Navigator 外層，推上去的頁面與對話框也一起遮住
      builder: (context, child) => AppLockGate(child: child ?? const SizedBox.shrink()),
      home: home,
    );
  }
}

/// 依登入狀態決定畫面：還原 session 中 → 標誌；沒登入 → 登入頁；登入後 → 驗證碼
class RootView extends StatelessWidget {
  const RootView({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final Widget child = switch (auth.status) {
      AuthStatus.loading => const _Splash(),
      AuthStatus.signedOut => const LoginPage(),
      AuthStatus.signedIn when auth.profile != null => const HomeShell(),
      AuthStatus.signedIn when auth.profileError != null => _ProfileError(message: auth.profileError!),
      AuthStatus.signedIn => const _Splash(),
    };
    return child;
  }
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) => const Scaffold(body: Center(child: AppLogo(size: 64)));
}

// 載入使用者資料失敗（第一次登入就沒有網路之類）：可以重試或登出
class _ProfileError extends StatelessWidget {
  const _ProfileError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthController>();
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                EmptyState(title: '載入使用者資料失敗', message: message, actionLabel: '重試', onAction: auth.loadProfile),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: auth.signOut,
                  style: TextButton.styleFrom(foregroundColor: context.colors.inkMuted),
                  child: const Text('登出'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 沒有帶入 Supabase 設定時（忘了 --dart-define-from-file）
class MissingConfigApp extends StatelessWidget {
  const MissingConfigApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      locale: _locale,
      supportedLocales: const [_locale],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: const Scaffold(
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: EmptyState(
              title: '缺少連線設定',
              message: '請用 --dart-define-from-file=env.json 啟動，env.json 的格式見 env.example.json',
            ),
          ),
        ),
      ),
    );
  }
}
