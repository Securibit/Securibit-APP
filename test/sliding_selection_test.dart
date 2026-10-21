import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:securibit/core/widgets/sliding_selection.dart';

const _color = Color(0xFF00FF00);

Widget _list(int selected, {bool reduceMotion = false}) => MediaQuery(
      data: MediaQueryData(disableAnimations: reduceMotion),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 100,
            child: SlidingSelection(
              selectedIndex: selected,
              color: _color,
              borderRadius: BorderRadius.zero,
              children: const [SizedBox(height: 40), SizedBox(height: 40), SizedBox(height: 40)],
            ),
          ),
        ),
      ),
    );

RRect _row(int index) => RRect.fromRectAndRadius(Rect.fromLTWH(0, 40.0 * index, 100, 40), Radius.zero);

void main() {
  testWidgets('換選項時底色從舊的位置滑到新的位置', (tester) async {
    await tester.pumpWidget(_list(0));
    final box = find.byType(SlidingSelection);
    expect(box, paints..rrect(rrect: _row(0), color: _color));

    await tester.pumpWidget(_list(2));
    // 動畫進行到一半：不在起點也不在終點
    await tester.pump(const Duration(milliseconds: 100));
    expect(box, isNot(paints..rrect(rrect: _row(0))));
    expect(box, isNot(paints..rrect(rrect: _row(2))));

    await tester.pump(SlidingSelection.duration);
    expect(box, paints..rrect(rrect: _row(2), color: _color));
  });

  testWidgets('減少動態效果時直接跳到新的位置', (tester) async {
    await tester.pumpWidget(_list(0, reduceMotion: true));
    await tester.pumpWidget(_list(1, reduceMotion: true));
    await tester.pump();
    expect(find.byType(SlidingSelection), paints..rrect(rrect: _row(1), color: _color));
  });

  testWidgets('沒有選中時不畫底色', (tester) async {
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: SlidingSelection(selectedIndex: null, color: _color, children: const [SizedBox(height: 40)]),
    ));
    expect(find.byType(SlidingSelection), isNot(paints..rrect()));
  });
}
