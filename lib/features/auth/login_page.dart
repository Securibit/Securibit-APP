import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/tokens.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/logo.dart';
import 'auth_controller.dart';

// 沒有登入時唯一的畫面：標誌、名稱、登入按鈕
class LoginPage extends StatelessWidget {
  const LoginPage({super.key});

  Future<void> _signIn(BuildContext context) async {
    final error = await context.read<AuthController>().signInWithGoogle();
    if (error != null && context.mounted) await showErrorDialog(context, '登入失敗', error);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final signingIn = context.select<AuthController, bool>((a) => a.signingIn);
    final usesBrowser = context.read<AuthController>().usesBrowser;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 340),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Center(child: AppLogo(size: 80)),
                  const SizedBox(height: 16),
                  const Text(
                    'Securibit',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 30, fontWeight: FontWeight.w700, letterSpacing: -0.3),
                  ),
                  const SizedBox(height: 40),
                  FilledButton(
                    onPressed: signingIn ? null : () => _signIn(context),
                    child: Text(signingIn ? (usesBrowser ? '請在瀏覽器完成登入' : '登入中…') : '使用 Google 登入'),
                  ),
                  // 原生帳號選單自己有取消鍵，只有瀏覽器登入需要
                  if (signingIn && usesBrowser) ...[
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: context.read<AuthController>().cancelSignIn,
                      style: TextButton.styleFrom(foregroundColor: colors.inkMuted),
                      child: const Text('取消'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
