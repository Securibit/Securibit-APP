import 'package:flutter/material.dart';

// 幣友的標誌（同網站導覽列）
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 28});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Image.asset('assets/logo.png', width: size, height: size, filterQuality: FilterQuality.medium);
  }
}
