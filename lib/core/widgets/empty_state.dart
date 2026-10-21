import 'package:flutter/material.dart';

import '../theme/tokens.dart';

// 空狀態：軟底圓角卡片，一行粗體標題、一行灰字說明，可帶一個動作
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.title, this.message, this.actionLabel, this.onAction, this.icon});

  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      decoration: BoxDecoration(color: colors.surface1, borderRadius: BorderRadius.circular(AppRadius.medium)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 28, color: colors.inkMuted), const SizedBox(height: 12)],
          Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w600)),
          if (message != null) ...[
            const SizedBox(height: 6),
            Text(message!, textAlign: TextAlign.center, style: TextStyle(fontSize: AppText.secondary, color: colors.inkMuted)),
          ],
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 12),
            TextButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    );
  }
}
