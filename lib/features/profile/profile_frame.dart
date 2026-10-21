import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import '../admin/widgets/admin_widgets.dart';

/// 個人資料的頁面：寬視窗用對話框（同設定），窄螢幕用整頁
Future<void> showProfilePage(BuildContext context, Widget Function(bool inDialog) builder) {
  if (MediaQuery.sizeOf(context).width >= 720) {
    return showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 560, maxHeight: 760), child: builder(true)),
      ),
    );
  }
  return Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => builder(false)));
}

/// 頁面外框：上面是標題（對話框時右邊是「完成」，整頁時左邊是返回），下面是置中的捲動內容
class ProfilePageScaffold extends StatelessWidget {
  const ProfilePageScaffold({
    super.key,
    required this.title,
    required this.inDialog,
    required this.children,
    this.onRefresh,
  });

  final String title;
  final bool inDialog;
  final List<Widget> children;
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.surface,
      appBar: AppBar(
        title: Text(title),
        automaticallyImplyLeading: !inDialog,
        actions: inDialog
            ? [
                TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('完成')),
                const SizedBox(width: 8),
              ]
            : null,
      ),
      body: SafeArea(top: false, child: AdminScrollBody(maxWidth: 640, onRefresh: onRefresh, children: children)),
    );
  }
}
