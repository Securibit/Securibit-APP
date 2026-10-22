import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import 'release.dart';

/*
 * 更新提示裡的 Release 說明：標題、段落、清單（可縮排）與表格，
 * 行內的 **粗體**、`程式碼`、[連結](網址)（只顯示文字，不能點）。
 */
class ReleaseNotesView extends StatelessWidget {
  const ReleaseNotesView({super.key, required this.blocks});

  final List<NoteBlock> blocks;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final base = TextStyle(fontSize: AppText.secondary, color: colors.ink, height: 1.5);
    final children = <Widget>[];
    for (final (index, block) in blocks.indexed) {
      final previous = index == 0 ? null : blocks[index - 1].type;
      switch (block.type) {
        case NoteBlockType.heading:
          if (index > 0) children.add(const SizedBox(height: 14));
          children.add(Text.rich(
            _inline(block.text, base, colors),
            style: base.copyWith(fontSize: block.depth <= 2 ? AppText.body : AppText.secondary, fontWeight: FontWeight.w700),
          ));
          children.add(const SizedBox(height: 4));
        case NoteBlockType.paragraph:
          if (index > 0 && previous != NoteBlockType.heading) children.add(const SizedBox(height: 8));
          children.add(Text.rich(_inline(block.text, base, colors), style: base));
        case NoteBlockType.bullet:
          if (previous == NoteBlockType.paragraph || previous == NoteBlockType.table) children.add(const SizedBox(height: 4));
          children.add(Padding(
            padding: EdgeInsets.only(left: block.depth * 16.0, top: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: block.marker == '•' ? 14 : 22,
                  child: Text(block.marker, style: base.copyWith(color: colors.inkMuted)),
                ),
                Expanded(child: Text.rich(_inline(block.text, base, colors), style: base)),
              ],
            ),
          ));
        case NoteBlockType.table:
          if (index > 0) children.add(const SizedBox(height: 8));
          children.add(_table(block.rows, base, colors));
      }
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: children);
  }

  Widget _table(List<List<String>> rows, TextStyle base, AppColors colors) {
    final columns = rows.fold<int>(0, (max, row) => row.length > max ? row.length : max);
    return Table(
      border: TableBorder(horizontalInside: BorderSide(color: colors.line, width: 0.5)),
      defaultVerticalAlignment: TableCellVerticalAlignment.top,
      children: [
        for (final (index, row) in rows.indexed)
          TableRow(
            children: [
              for (var i = 0; i < columns; i++)
                Padding(
                  padding: const EdgeInsets.fromLTRB(0, 5, 10, 5),
                  child: Text.rich(
                    _inline(i < row.length ? row[i] : '', base, colors),
                    style: index == 0 ? base.copyWith(fontWeight: FontWeight.w700) : base,
                  ),
                ),
            ],
          ),
      ],
    );
  }

  // 行內格式：**粗體**、`程式碼`、[連結](網址)
  static final _inlinePattern = RegExp(r'(\*\*|__)(.+?)\1|`([^`]+)`|!?\[([^\]]*)\]\([^)]*\)');

  TextSpan _inline(String text, TextStyle base, AppColors colors) {
    final spans = <InlineSpan>[];
    var start = 0;
    for (final match in _inlinePattern.allMatches(text)) {
      if (match.start > start) spans.add(TextSpan(text: text.substring(start, match.start)));
      if (match[2] != null) {
        spans.add(TextSpan(text: match[2], style: const TextStyle(fontWeight: FontWeight.w700)));
      } else if (match[3] != null) {
        spans.add(TextSpan(
          text: match[3],
          style: TextStyle(fontFamily: 'Menlo', fontFamilyFallback: const ['monospace'], fontSize: AppText.caption, color: colors.ink, backgroundColor: colors.surface2),
        ));
      } else {
        spans.add(TextSpan(text: match[4]));
      }
      start = match.end;
    }
    if (start < text.length) spans.add(TextSpan(text: text.substring(start)));
    return TextSpan(children: spans);
  }
}
