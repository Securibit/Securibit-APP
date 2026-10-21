import 'package:flutter/material.dart';

import '../../core/platform.dart';
import '../auth/login_page.dart';
import 'onboarding_view.dart';

/// 沒登入時要不要先看介紹頁：只有手機（iOS、Android）有，桌面版直接進登入頁；
/// 看過（按了開始使用或略過）就進登入頁
bool shouldShowOnboarding({required bool mobile, required bool introDone}) => mobile && !introDone;

/*
 * 沒登入時的畫面：手機先看介紹頁，再到登入頁；桌面直接是登入頁。
 * 「看過了」只記在這個畫面上：登入後這個畫面就拆掉了，之後登出或下次開 App 沒登入時會再看到介紹頁。
 */
class SignedOutView extends StatefulWidget {
  const SignedOutView({super.key, this.mobile});

  // 測試用：指定是不是手機，不給就看目前的平台
  final bool? mobile;

  @override
  State<SignedOutView> createState() => _SignedOutViewState();
}

class _SignedOutViewState extends State<SignedOutView> {
  bool _introDone = false;

  @override
  Widget build(BuildContext context) {
    final intro = shouldShowOnboarding(mobile: widget.mobile ?? AppPlatform.isMobile, introDone: _introDone);
    return AnimatedSwitcher(
      duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 320),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      child: intro
          ? OnboardingView(key: const ValueKey('intro'), onDone: () => setState(() => _introDone = true))
          : const LoginPage(key: ValueKey('login')),
    );
  }
}
