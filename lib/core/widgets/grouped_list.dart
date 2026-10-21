import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// iOS 設定式的分組清單：圓角 18 的軟底，列與列之間有髮絲線
class GroupedList extends StatelessWidget {
  const GroupedList({super.key, this.header, this.footer, required this.children});

  final String? header;
  final String? footer;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) rows.add(Divider(indent: 16, height: 0.5, color: colors.line.withValues(alpha: 0.6)));
      rows.add(children[i]);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (header != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(header!, style: TextStyle(fontSize: AppText.caption, color: colors.inkMuted, fontWeight: FontWeight.w500)),
          ),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.medium),
          child: ColoredBox(color: colors.surface1, child: Column(children: rows)),
        ),
        if (footer != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(footer!, style: TextStyle(fontSize: AppText.caption, color: colors.inkMuted)),
          ),
      ],
    );
  }
}

/// 分組清單的一列：左邊標籤、右邊值或其他元件
class GroupedRow extends StatelessWidget {
  const GroupedRow({
    super.key,
    required this.label,
    this.value,
    this.trailing,
    this.onTap,
    this.danger = false,
    this.accent = false,
    this.leading,
  });

  final String label;
  final String? value;
  final Widget? trailing;
  final Widget? leading;
  final VoidCallback? onTap;
  final bool danger;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final labelColor = danger ? colors.alarm : (accent ? colors.accent : colors.ink);
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 50),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              if (leading != null) ...[leading!, const SizedBox(width: 12)],
              Text(label, style: TextStyle(fontSize: AppText.body, color: labelColor, fontWeight: danger || accent ? FontWeight.w600 : FontWeight.w400)),
              const SizedBox(width: 12),
              Expanded(
                child: value == null
                    ? const SizedBox.shrink()
                    : Text(
                        value!,
                        textAlign: TextAlign.right,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: AppText.body, color: colors.inkMuted),
                      ),
              ),
              if (trailing != null) ...[const SizedBox(width: 8), trailing!],
            ],
          ),
        ),
      ),
    );
  }
}
