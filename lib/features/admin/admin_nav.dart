import 'package:flutter/material.dart';

/*
 * 後台的版面切換：寬度夠時「清單｜詳細資料」並排，不夠時清單一頁、點一筆開下一頁（同主畫面的 Proton 版面）。
 * 跨區塊的連結（使用者 → 群組、成員 → 使用者）一律開新的一頁。
 */

/// 「清單｜詳細資料」並排需要的寬度
const adminSplitWidth = 760.0;

/// 清單欄的寬度
const adminListWidth = 360.0;

/// 開一頁詳細資料（上面只有返回鍵，標題在內容裡）
Future<T?> pushAdminPage<T>(BuildContext context, Widget body, {String? title}) {
  return Navigator.of(context).push<T>(MaterialPageRoute(
    builder: (_) => Scaffold(appBar: AppBar(title: title == null ? null : Text(title)), body: SafeArea(top: false, child: body)),
  ));
}

/// 清單與詳細資料：寬的時候並排（選中的那一筆在右邊），窄的時候點一筆開下一頁
class MasterDetail extends StatelessWidget {
  const MasterDetail({
    super.key,
    required this.list,
    required this.detail,
    required this.selectedId,
    required this.placeholder,
  });

  // split：是否並排（窄的時候清單點一筆要自己開下一頁）
  final Widget Function(BuildContext context, bool split) list;
  final Widget Function(BuildContext context, String id) detail;
  final String? selectedId;
  final Widget placeholder;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final split = constraints.maxWidth >= adminSplitWidth;
        if (!split) return list(context, false);
        final line = Theme.of(context).dividerTheme.color;
        return Row(
          children: [
            SizedBox(width: adminListWidth, child: list(context, true)),
            VerticalDivider(width: 0.5, thickness: 0.5, color: line),
            Expanded(
              child: selectedId == null
                  ? placeholder
                  : KeyedSubtree(key: ValueKey(selectedId), child: detail(context, selectedId!)),
            ),
          ],
        );
      },
    );
  }
}
