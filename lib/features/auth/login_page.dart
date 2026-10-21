import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/tokens.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/logo.dart';
import '../onboarding/live_demo.dart';
import 'auth_controller.dart';
import 'google_mark.dart';

/*
 * 沒有登入時的登入頁：標誌、一句話、一筆真的會跳的示範驗證碼，最下面是 Google 登入。
 * 窄螢幕（手機）由上往下排；寬視窗（桌面）左邊文字與按鈕、右邊驗證碼。
 * 登入方式不變：手機有設定用戶端 ID 時用原生帳號選單，其他用瀏覽器登入。
 */
class LoginPage extends StatelessWidget {
  const LoginPage({super.key});

  static const _headline = '驗證碼，終於有地方放了';
  static const _lead = '換手機不用重綁，金鑰可以加密，還能和家人、團隊共用';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: _Entrance(
          child: LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth >= 760 && constraints.maxHeight >= 440) return _wide(context);
              return _narrow(context, constraints);
            },
          ),
        ),
      ),
    );
  }

  Widget _narrow(BuildContext context, BoxConstraints constraints) {
    final colors = context.colors;
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: constraints.maxHeight),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            // 整組在畫面中間，太矮時可以捲動
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 16),
                const _Brand(center: true),
                const SizedBox(height: 28),
                const Text(
                  _headline,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 30, fontWeight: FontWeight.w700, height: 1.25, letterSpacing: -0.3),
                ),
                const SizedBox(height: 10),
                Text(_lead, textAlign: TextAlign.center, style: TextStyle(fontSize: AppText.body, height: 1.5, color: colors.inkMuted)),
                const SizedBox(height: 32),
                const DemoHeroCode(),
                const SizedBox(height: 32),
                const _SignInActions(center: true),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _wide(BuildContext context) {
    final colors = context.colors;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(40),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const _Brand(center: false),
                    const SizedBox(height: 28),
                    const Text(
                      _headline,
                      style: TextStyle(fontSize: 36, fontWeight: FontWeight.w700, height: 1.2, letterSpacing: -0.4),
                    ),
                    const SizedBox(height: 12),
                    Text(_lead, style: TextStyle(fontSize: AppText.body, height: 1.5, color: colors.inkMuted)),
                    const SizedBox(height: 36),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 340),
                      child: _SignInActions(center: false),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 56),
              const SizedBox(width: 380, child: DemoHeroCode()),
            ],
          ),
        ),
      ),
    );
  }
}

class _Brand extends StatelessWidget {
  const _Brand({required this.center});

  final bool center;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: center ? MainAxisAlignment.center : MainAxisAlignment.start,
      children: [
        const AppLogo(size: 40),
        const SizedBox(width: 10),
        Text('Securibit', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700, color: context.colors.ink)),
      ],
    );
  }
}

// Google 登入按鈕、登入中的取消、一行說明
class _SignInActions extends StatelessWidget {
  const _SignInActions({required this.center});

  final bool center;

  Future<void> _signIn(BuildContext context) async {
    final error = await context.read<AuthController>().signInWithGoogle();
    if (error != null && context.mounted) await showErrorDialog(context, '登入失敗', error);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final signingIn = context.select<AuthController, bool>((a) => a.signingIn);
    final usesBrowser = context.read<AuthController>().usesBrowser;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton(
          onPressed: signingIn ? null : () => _signIn(context),
          style: FilledButton.styleFrom(minimumSize: const Size(64, 54)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 白色圓底上的 G，在綠色按鈕上也看得清楚
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                child: signingIn && !usesBrowser
                    ? const SizedBox.square(dimension: 14, child: CircularProgressIndicator(strokeWidth: 2))
                    : const GoogleMark(size: 16),
              ),
              const SizedBox(width: 12),
              Flexible(child: Text(signingIn ? (usesBrowser ? '請在瀏覽器完成登入' : '登入中…') : '使用 Google 登入')),
            ],
          ),
        ),
        // 原生帳號選單自己有取消鍵，只有瀏覽器登入需要
        if (signingIn && usesBrowser) ...[
          const SizedBox(height: 8),
          TextButton(
            onPressed: context.read<AuthController>().cancelSignIn,
            style: TextButton.styleFrom(foregroundColor: colors.inkMuted),
            child: const Text('取消'),
          ),
        ] else ...[
          const SizedBox(height: 14),
          Text(
            '和網站 2fa.bityo.tw 用同一個帳號',
            textAlign: center ? TextAlign.center : TextAlign.start,
            style: TextStyle(fontSize: AppText.caption, fontWeight: FontWeight.w500, color: colors.inkMuted),
          ),
        ],
      ],
    );
  }
}

// 進場：淡入並往上移一點；減少動態效果時直接出現
class _Entrance extends StatelessWidget {
  const _Entrance({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 520),
      curve: Curves.easeOutCubic,
      child: child,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(0, 16 * (1 - t)), child: child),
      ),
    );
  }
}
