import 'package:flutter/material.dart';

import '../theme/tokens.dart';

// 幣友的標誌（同網站導覽列）
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 28});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Image.asset('assets/logo.png', width: size, height: size, filterQuality: FilterQuality.medium);
  }
}

/*
 * 只有盾牌本身（裁掉 logo.png 四周的透明留白），用來跟文字排在同一行。
 * logo.png 是 512×512，盾牌佔中間約 288×345；圓餅的缺口是透明的，會透出底色。
 */
class AppMark extends StatelessWidget {
  const AppMark({super.key, this.height = 44});

  final double height;

  static const _canvas = 512.0;
  static const _markWidth = 288.0;
  static const _markHeight = 345.0;

  @override
  Widget build(BuildContext context) {
    final image = height * _canvas / _markHeight;
    return SizedBox(
      width: height * _markWidth / _markHeight,
      height: height,
      child: OverflowBox(
        maxWidth: image,
        maxHeight: image,
        child: Image.asset('assets/logo.png', width: image, height: image, filterQuality: FilterQuality.medium),
      ),
    );
  }
}

// 鎖定畫面底部的署名：綠色的幣友標誌＋「幣友 BITYO 出品」
class BityoCredit extends StatelessWidget {
  const BityoCredit({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ExcludeSemantics(
          child: Image.asset('assets/bityo.png', width: 24, height: 24, color: colors.accent, filterQuality: FilterQuality.medium),
        ),
        const SizedBox(width: 7),
        Text('幣友 BITYO 出品', style: TextStyle(fontSize: AppText.caption, color: colors.inkMuted)),
      ],
    );
  }
}
