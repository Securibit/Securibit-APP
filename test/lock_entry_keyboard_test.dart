import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:securibit/core/theme/app_theme.dart';
import 'package:securibit/features/settings/lock/lock_entry.dart';
import 'package:securibit/features/settings/lock/lock_secret.dart';

// 密碼畫面的鍵盤輸入：不用先點畫面，上排數字鍵與數字小鍵盤都能輸入，別的輸入框拿著焦點時也一樣
void main() {
  Future<List<String>> pump(WidgetTester tester, {bool withTextField = false}) async {
    final submitted = <String>[];
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.dark),
      home: Scaffold(
        body: Column(
          children: [
            if (withTextField) const TextField(autofocus: true),
            Expanded(
              child: LockEntry(
                type: LockType.pin4,
                title: '輸入密碼',
                onSubmit: (secret) async {
                  submitted.add(secret);
                  return true;
                },
              ),
            ),
          ],
        ),
      ),
    ));
    await tester.pump();
    return submitted;
  }

  testWidgets('數字小鍵盤與上排數字鍵都能輸入，Backspace 刪除', (tester) async {
    final submitted = await pump(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.numpad1);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit2);
    await tester.sendKeyEvent(LogicalKeyboardKey.numpad9);
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.sendKeyEvent(LogicalKeyboardKey.numpad3);
    await tester.sendKeyEvent(LogicalKeyboardKey.numpad4);
    await tester.pumpAndSettle();
    expect(submitted, ['1234']);
  });

  testWidgets('Num Lock 關掉時數字小鍵盤送出的是 End、↓ 等，也照實體位置當成數字', (tester) async {
    final submitted = await pump(tester);
    for (final (physical, logical) in [
      (PhysicalKeyboardKey.numpad1, LogicalKeyboardKey.end),
      (PhysicalKeyboardKey.numpad2, LogicalKeyboardKey.arrowDown),
      (PhysicalKeyboardKey.numpad0, LogicalKeyboardKey.insert),
      (PhysicalKeyboardKey.numpad7, LogicalKeyboardKey.home),
    ]) {
      await tester.sendKeyDownEvent(logical, physicalKey: physical);
      await tester.sendKeyUpEvent(logical, physicalKey: physical);
    }
    await tester.pumpAndSettle();
    expect(submitted, ['1207']);
  });

  testWidgets('別的輸入框拿著焦點時也收得到', (tester) async {
    final submitted = await pump(tester, withTextField: true);
    for (final key in [LogicalKeyboardKey.numpad5, LogicalKeyboardKey.numpad6, LogicalKeyboardKey.numpad7, LogicalKeyboardKey.numpad8]) {
      await tester.sendKeyEvent(key);
    }
    await tester.pumpAndSettle();
    expect(submitted, ['5678']);
  });
}
