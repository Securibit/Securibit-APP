import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:securibit/core/theme/app_theme.dart';
import 'package:securibit/features/settings/lock/app_lock_controller.dart';
import 'package:securibit/features/settings/settings_controller.dart';
import 'package:securibit/features/shell/collapsible_sidebar.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_lock_test.dart' show MemoryLockStorage;

const _key = 'securibit:sidebarCollapsed';

Future<SettingsController> loadSettings(WidgetTester tester) async {
  final settings = SettingsController(appLock: AppLockController(storage: MemoryLockStorage(), iterations: 1000));
  await tester.runAsync(settings.load);
  return settings;
}

// 同 HomeShell：側欄最上面有收起鍵，收起來後內容左上角才有打開鍵
Widget shell(SettingsController settings) => ChangeNotifierProvider.value(
      value: settings,
      child: MaterialApp(
        theme: buildTheme(Brightness.light),
        home: Scaffold(
          body: CollapsibleSidebar(
            sidebar: const Column(children: [SidebarToggleButton(key: Key('hide')), Text('側欄內容')]),
            child: Consumer<SettingsController>(
              builder: (context, s, _) => Align(
                alignment: Alignment.topLeft,
                child: s.sidebarCollapsed ? const SidebarToggleButton(key: Key('show')) : const SizedBox.shrink(),
              ),
            ),
          ),
        ),
      ),
    );

Future<void> pressShortcut(WidgetTester tester) async {
  final modifiers = Platform.isMacOS
      ? [LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.metaLeft]
      : [LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.shiftLeft];
  for (final key in modifiers) {
    await tester.sendKeyDownEvent(key);
  }
  await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
  for (final key in modifiers.reversed) {
    await tester.sendKeyUpEvent(key);
  }
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('預設打開；按收起鍵收起來並記住，再按打開鍵打開', (tester) async {
    final settings = await loadSettings(tester);
    expect(settings.sidebarCollapsed, isFalse);
    await tester.pumpWidget(shell(settings));
    expect(SidebarCommands.available.value, isTrue);
    expect(find.text('側欄內容').hitTestable(), findsOneWidget);
    expect(find.byKey(const Key('show')), findsNothing);

    await tester.tap(find.byKey(const Key('hide')));
    await tester.pumpAndSettle();
    expect(settings.sidebarCollapsed, isTrue);
    expect(find.text('側欄內容').hitTestable(), findsNothing);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(_key), isTrue);

    await tester.tap(find.byKey(const Key('show')));
    await tester.pumpAndSettle();
    expect(settings.sidebarCollapsed, isFalse);
    expect(find.text('側欄內容').hitTestable(), findsOneWidget);
    expect(prefs.getBool(_key), isFalse);

    // 拿掉之後 Mac 選單的項目變灰
    await tester.pumpWidget(const SizedBox());
    expect(SidebarCommands.available.value, isFalse);
  });

  testWidgets('收起來的過程中不會超出版面', (tester) async {
    final settings = await loadSettings(tester);
    await tester.pumpWidget(shell(settings));
    settings.toggleSidebar();
    await tester.pump();
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 40));
      expect(tester.takeException(), isNull);
    }
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(CollapsibleSidebar)).width, 800);
  });

  testWidgets('快捷鍵切換（macOS ⌃⌘S，Windows、Linux Ctrl+Shift+S）', (tester) async {
    final settings = await loadSettings(tester);
    await tester.pumpWidget(shell(settings));

    await pressShortcut(tester);
    expect(settings.sidebarCollapsed, isTrue);
    expect(find.text('側欄內容').hitTestable(), findsNothing);

    await pressShortcut(tester);
    expect(settings.sidebarCollapsed, isFalse);

    // 只按 S、或少了修飾鍵都不算
    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(settings.sidebarCollapsed, isFalse);
  });

  testWidgets('快捷鍵依平台判斷', (tester) async {
    final results = <String>[];
    bool record(KeyEvent event) {
      if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.keyS) {
        results.add('mac:${isSidebarShortcut(event, mac: true)} other:${isSidebarShortcut(event, mac: false)}');
      }
      return false;
    }

    HardwareKeyboard.instance.addHandler(record);
    addTearDown(() => HardwareKeyboard.instance.removeHandler(record));
    Future<void> press(List<LogicalKeyboardKey> modifiers) async {
      for (final key in modifiers) {
        await tester.sendKeyDownEvent(key);
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
      for (final key in modifiers.reversed) {
        await tester.sendKeyUpEvent(key);
      }
    }

    await press([LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.metaLeft]);
    await press([LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.shiftLeft]);
    await press([LogicalKeyboardKey.metaLeft]);
    await press([LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.metaLeft, LogicalKeyboardKey.shiftLeft]);
    expect(results, ['mac:true other:false', 'mac:false other:true', 'mac:false other:false', 'mac:false other:false']);
  });

  testWidgets('重新開啟時照上次的狀態', (tester) async {
    SharedPreferences.setMockInitialValues({_key: true});
    final settings = await loadSettings(tester);
    expect(settings.sidebarCollapsed, isTrue);
    await tester.pumpWidget(shell(settings));
    expect(find.text('側欄內容').hitTestable(), findsNothing);
    expect(find.byKey(const Key('show')), findsOneWidget);
  });
}
