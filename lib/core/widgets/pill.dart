import 'package:flutter/material.dart';

import '../theme/tokens.dart';

// 藥丸按鈕（類別篩選），選中時反白，同網站
class Pill extends StatelessWidget {
  const Pill({super.key, required this.label, required this.active, required this.onTap});

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Material(
      color: active ? colors.ink : colors.surface1,
      shape: const StadiumBorder(),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          child: Text(
            label,
            style: TextStyle(
              fontSize: AppText.secondary,
              fontWeight: FontWeight.w600,
              color: active ? colors.surface : colors.ink,
            ),
          ),
        ),
      ),
    );
  }
}
