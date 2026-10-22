import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'logo.dart';

/*
 * 鎖定畫面（App 鎖定、加密群組解鎖）的底：上淺下深的漸層，上方中間透出一圈很淡的幣友綠。
 * 漸層的顏色只用在這裡，所以不放進 AppColors。
 */
class LockBackdrop extends StatelessWidget {
  const LockBackdrop({super.key, required this.child});

  final Widget child;

  static const _darkTop = Color(0xFF24262C);
  static const _darkBottom = Color(0xFF16171B);
  static const _lightTop = Color(0xFFFFFFFF);
  static const _lightBottom = Color(0xFFF2F3F5);

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: dark ? const [_darkTop, _darkBottom] : const [_lightTop, _lightBottom],
        ),
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.topCenter,
            radius: 0.75,
            colors: [colors.brand.withValues(alpha: dark ? 0.09 : 0.07), colors.brand.withValues(alpha: 0)],
            transform: const _Stretch(),
          ),
        ),
        child: child,
      ),
    );
  }
}

// 光暈照畫面比例拉成橢圓（半徑是寬、高各自的比例，跟設計稿的 SVG 一樣），不然寬視窗上只是一小圈
class _Stretch extends GradientTransform {
  const _Stretch();

  @override
  Matrix4 transform(Rect bounds, {TextDirection? textDirection}) {
    final side = bounds.shortestSide;
    if (side == 0) return Matrix4.identity();
    final cx = bounds.center.dx;
    final cy = bounds.top;
    return Matrix4.translationValues(cx, cy, 0)
      ..multiply(Matrix4.diagonal3Values(bounds.width / side, bounds.height / side, 1))
      ..multiply(Matrix4.translationValues(-cx, -cy, 0));
  }
}

// 鎖定畫面的標題：「解鎖」＋盾牌＋「Securibit」
class UnlockTitle extends StatelessWidget {
  const UnlockTitle({super.key});

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(fontSize: 30, fontWeight: FontWeight.w600, color: context.colors.ink, height: 1.2);
    return Semantics(
      header: true,
      label: '解鎖 Securibit',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('解鎖', style: style),
          const SizedBox(width: 8),
          const AppMark(height: 44),
          const SizedBox(width: 8),
          Text('Securibit', style: style),
        ],
      ),
    );
  }
}
