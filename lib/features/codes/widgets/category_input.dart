import 'package:flutter/material.dart';

import '../../../core/theme/tokens.dart';
import '../totp/categories.dart';

/*
 * 類別欄位（同網站 CategoryInput）：已選的類別是小藥丸，可以移除；
 * 輸入後按 Enter 或打逗號加入；下面列出既有類別，點一下就加入。
 */
class CategoryInput extends StatefulWidget {
  const CategoryInput({super.key, required this.value, required this.onChanged, required this.suggestions});

  // 「,」串起來的字串
  final String value;
  final ValueChanged<String> onChanged;
  final List<String> suggestions;

  @override
  State<CategoryInput> createState() => _CategoryInputState();
}

class _CategoryInputState extends State<CategoryInput> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<String> get _selected => parseCategories(widget.value);

  void _add(String text) {
    final added = parseCategories(text);
    if (added.isEmpty) return;
    widget.onChanged(joinCategories([..._selected, ...added]));
  }

  void _remove(String name) => widget.onChanged(joinCategories(_selected.where((c) => c != name).toList()));

  void _onChanged(String text) {
    // 打了分隔符號就把前面的字加進去
    if (RegExp(r'[,，、]').hasMatch(text)) {
      _add(text);
      _controller.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final selected = _selected;
    final suggestions = widget.suggestions.where((s) => !selected.contains(s)).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (selected.isNotEmpty) ...[
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final name in selected)
                InputChip(
                  label: Text(name, style: const TextStyle(fontSize: AppText.secondary, fontWeight: FontWeight.w600)),
                  onDeleted: () => _remove(name),
                  deleteButtonTooltipMessage: '移除',
                  backgroundColor: colors.surface2,
                  side: BorderSide.none,
                  shape: const StadiumBorder(),
                ),
            ],
          ),
          const SizedBox(height: 8),
        ],
        TextField(
          controller: _controller,
          onChanged: _onChanged,
          onSubmitted: (text) {
            _add(text);
            _controller.clear();
          },
          onTapOutside: (_) {
            if (_controller.text.trim().isNotEmpty) {
              _add(_controller.text);
              _controller.clear();
            }
          },
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(hintText: '例如：工作、個人', helperText: '可以有多個類別，按 Enter 或打逗號加入'),
        ),
        if (suggestions.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final name in suggestions)
                ActionChip(
                  label: Text('+ $name', style: TextStyle(fontSize: AppText.secondary, color: colors.accent, fontWeight: FontWeight.w600)),
                  onPressed: () => _add(name),
                  backgroundColor: colors.surface1,
                  side: BorderSide.none,
                  shape: const StadiumBorder(),
                ),
            ],
          ),
        ],
      ],
    );
  }
}
