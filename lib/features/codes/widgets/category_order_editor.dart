import 'package:flutter/material.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/widgets/feedback.dart';
import '../codes_controller.dart';

/// 「調整類別順序」：寬視窗用對話框，窄螢幕開整頁（同新增驗證碼）；儲存後提示一次
Future<void> showCategoryOrderEditor(BuildContext context, CodesController controller) async {
  final editor = CategoryOrderEditor(controller: controller);
  final bool? saved;
  if (MediaQuery.sizeOf(context).width >= 720) {
    saved = await showDialog<bool>(
      context: context,
      builder: (context) => Dialog(
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 440, maxHeight: 620), child: editor),
      ),
    );
  } else {
    saved = await Navigator.of(context).push(MaterialPageRoute<bool>(fullscreenDialog: true, builder: (_) => editor));
  }
  if (saved == true && context.mounted) showToast(context, '已更新類別順序');
}

/*
 * 類別的自訂順序（所有成員共用，存在資料庫）：拖曳左邊的把手或用右邊的箭頭調整，按「儲存」才送出，「取消」不保留。
 * 篩選列與新增驗證碼的類別建議都照這個順序，之後新出現的類別照字母排在後面。
 */
class CategoryOrderEditor extends StatefulWidget {
  const CategoryOrderEditor({super.key, required this.controller});

  final CodesController controller;

  @override
  State<CategoryOrderEditor> createState() => _CategoryOrderEditorState();
}

class _CategoryOrderEditorState extends State<CategoryOrderEditor> {
  late final List<String> _original = widget.controller.categories;
  late List<String> _names = [..._original];
  bool _saving = false;

  bool get _changed => !_sameOrder(_names, _original);

  static bool _sameOrder(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  void _reorder(int oldIndex, int newIndex) {
    setState(() {
      final next = [..._names];
      final moving = next.removeAt(oldIndex);
      next.insert(newIndex > oldIndex ? newIndex - 1 : newIndex, moving);
      _names = next;
    });
  }

  // 箭頭：和相鄰的交換（offset −1 往上、1 往下）
  void _move(int index, int offset) {
    final target = index + offset;
    if (target < 0 || target >= _names.length) return;
    setState(() {
      final next = [..._names];
      next[index] = _names[target];
      next[target] = _names[index];
      _names = next;
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final error = await widget.controller.saveCategoryOrder(_names);
    if (!mounted) return;
    if (error != null) {
      setState(() => _saving = false);
      await showErrorDialog(context, '調整類別順序失敗', error);
      return;
    }
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return PopScope(
      canPop: !_saving,
      child: Scaffold(
        backgroundColor: colors.surface,
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(context),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: Text(
                  '拖曳或用箭頭調整順序，篩選與類別建議都照這個順序；順序對所有成員都一樣',
                  style: TextStyle(fontSize: AppText.secondary, color: colors.inkMuted),
                ),
              ),
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.medium),
                    child: ColoredBox(
                      color: colors.surface1,
                      child: ReorderableListView.builder(
                        shrinkWrap: true,
                        buildDefaultDragHandles: false,
                        itemCount: _names.length,
                        onReorder: _saving ? (_, _) {} : _reorder,
                        proxyDecorator: (child, _, _) => Material(
                          color: colors.surface2,
                          elevation: 4,
                          borderRadius: BorderRadius.circular(AppRadius.small),
                          child: child,
                        ),
                        itemBuilder: (context, index) => _CategoryRow(
                          key: ValueKey(_names[index]),
                          name: _names[index],
                          index: index,
                          last: index == _names.length - 1,
                          enabled: !_saving,
                          onUp: index > 0 ? () => _move(index, -1) : null,
                          onDown: index < _names.length - 1 ? () => _move(index, 1) : null,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      child: Row(
        children: [
          TextButton(
            onPressed: _saving ? null : () => Navigator.of(context).pop(false),
            style: TextButton.styleFrom(foregroundColor: colors.ink),
            child: const Text('取消'),
          ),
          const Expanded(
            child: Text(
              '調整類別順序',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: AppText.body, fontWeight: FontWeight.w700),
            ),
          ),
          TextButton(
            onPressed: _saving || !_changed ? null : _save,
            child: _saving
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('儲存'),
          ),
        ],
      ),
    );
  }
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({
    super.key,
    required this.name,
    required this.index,
    required this.last,
    required this.enabled,
    required this.onUp,
    required this.onDown,
  });

  final String name;
  final int index;
  final bool last;
  final bool enabled;
  final VoidCallback? onUp;
  final VoidCallback? onDown;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final handle = Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
      child: Icon(Icons.drag_indicator_rounded, size: 20, color: colors.inkMuted),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 50),
          child: Row(
            children: [
              if (enabled)
                ReorderableDragStartListener(
                  index: index,
                  child: MouseRegion(cursor: SystemMouseCursors.grab, child: Tooltip(message: '拖曳調整順序', child: handle)),
                )
              else
                handle,
              Expanded(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: AppText.body, fontWeight: FontWeight.w500),
                ),
              ),
              _MoveButton(icon: Icons.keyboard_arrow_up_rounded, tooltip: '往上移', onPressed: enabled ? onUp : null),
              _MoveButton(icon: Icons.keyboard_arrow_down_rounded, tooltip: '往下移', onPressed: enabled ? onDown : null),
              const SizedBox(width: 4),
            ],
          ),
        ),
        if (!last) Divider(indent: 40, height: 0.5, color: colors.line.withValues(alpha: 0.6)),
      ],
    );
  }
}

class _MoveButton extends StatelessWidget {
  const _MoveButton({required this.icon, required this.tooltip, required this.onPressed});

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        visualDensity: VisualDensity.compact,
        constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
        icon: Icon(icon),
      );
}
