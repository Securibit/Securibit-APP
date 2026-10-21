import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'sliding_selection.dart';

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

/// 一排藥丸（類別篩選）：選中的反白底色會從舊的藥丸滑到新的藥丸，不是原地換色
class PillBar extends StatelessWidget {
  const PillBar({super.key, required this.labels, required this.selectedIndex, required this.onSelect, this.padding = EdgeInsets.zero});

  final List<String> labels;
  final int? selectedIndex;
  final ValueChanged<int> onSelect;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: padding,
      child: SlidingSelection(
        direction: Axis.horizontal,
        selectedIndex: selectedIndex,
        color: colors.ink,
        itemColor: colors.surface1,
        spacing: 6,
        // 捲過去時讓旁邊的藥丸露出一點，看得出來還能捲
        revealPadding: const EdgeInsets.symmetric(horizontal: 40),
        children: [
          for (var i = 0; i < labels.length; i++) _PillLabel(label: labels[i], active: i == selectedIndex, onTap: () => onSelect(i)),
        ],
      ),
    );
  }
}

// 藥丸本身透明，底色由 SlidingSelection 畫；字色跟著底色一起漸變，字重固定所以寬度不會跳
class _PillLabel extends StatelessWidget {
  const _PillLabel({required this.label, required this.active, required this.onTap});

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final duration = MediaQuery.disableAnimationsOf(context) ? Duration.zero : SlidingSelection.duration;
    return Semantics(
      selected: active,
      button: true,
      child: Material(
        type: MaterialType.transparency,
        shape: const StadiumBorder(),
        child: InkWell(
          customBorder: const StadiumBorder(),
          highlightColor: Colors.transparent,
          focusColor: Colors.transparent,
          hoverColor: Colors.transparent,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            child: TweenAnimationBuilder<Color?>(
              tween: ColorTween(end: active ? colors.surface : colors.ink),
              duration: duration,
              curve: SlidingSelection.curve,
              builder: (context, color, _) => Text(
                label,
                style: TextStyle(fontSize: AppText.secondary, fontWeight: FontWeight.w600, color: color),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
