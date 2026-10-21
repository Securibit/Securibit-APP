import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/tokens.dart';

/// 底部的小提示（已複製、已儲存…）
void showToast(BuildContext context, String message) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(message),
      duration: const Duration(milliseconds: 1600),
      width: MediaQuery.sizeOf(context).width > 600 ? 360 : null,
    ));
}

/// 錯誤對話框：標題說明是什麼失敗，內文是原因（同網站的 showError）
Future<void> showErrorDialog(BuildContext context, String title, String message) {
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('好'))],
    ),
  );
}

/// 確認對話框；danger 時確認鍵是紅字
Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  bool danger = false,
}) async {
  final colors = context.colors;
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          style: TextButton.styleFrom(foregroundColor: colors.ink),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: danger ? TextButton.styleFrom(foregroundColor: colors.alarm) : null,
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// 複製到剪貼簿並提示
Future<void> copyText(BuildContext context, String text, {String message = '已複製'}) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (context.mounted) showToast(context, message);
}
