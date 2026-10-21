import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:securibit/features/auth/auth_controller.dart';
import 'package:securibit/features/cache/offline_cache.dart';
import 'package:securibit/features/settings/app_lock.dart';
import 'package:securibit/features/settings/lock/app_lock_controller.dart';
import 'package:securibit/features/settings/lock/lock_secret.dart';
import 'package:securibit/features/settings/lock/lock_setup_page.dart';
import 'package:securibit/features/settings/lock/pattern_pad.dart';
import 'package:securibit/features/settings/settings_controller.dart';
import 'package:securibit/core/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_lock_test.dart' show MemoryLockStorage;

// 鎖定畫面：冷啟動蓋住內容，密碼錯誤顯示提示，正確後回到原本的畫面
void main() {
  testWidgets('冷啟動要先解鎖，錯誤會提示，正確才看得到內容', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final lock = AppLockController(storage: MemoryLockStorage(), iterations: 1000);
    final settings = SettingsController(appLock: lock);
    await tester.runAsync(() async {
      await settings.load();
      await lock.setLock(LockType.pin4, '2580');
    });
    final auth = AuthController(cache: const OfflineCache(), onSignedIn: (_) {}, onSignedOut: (_) {});

    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: settings),
        ChangeNotifierProvider.value(value: auth),
      ],
      child: MaterialApp(
        theme: buildTheme(Brightness.light),
        builder: (context, child) => AppLockGate(child: child!),
        home: const Scaffold(body: Text('驗證碼內容')),
      ),
    ));

    expect(find.text('輸入密碼'), findsOneWidget);
    expect(find.text('驗證碼內容'), findsNothing);

    Future<void> enter(String pin) async {
      for (final digit in pin.split('')) {
        await tester.tap(find.bySemanticsLabel(digit).first);
        await tester.pump();
      }
      // 雜湊在背景 isolate 計算
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
      await tester.pumpAndSettle();
    }

    await enter('1111');
    expect(find.text('密碼錯誤'), findsOneWidget);
    expect(lock.attempts.failures, 1);
    expect(find.text('驗證碼內容'), findsNothing);

    await enter('2580');
    expect(find.text('輸入密碼'), findsNothing);
    expect(find.text('驗證碼內容'), findsOneWidget);
    expect(lock.attempts.failures, 0);
  });

  testWidgets('設定圖形要畫兩次一樣，太短或不一樣都不存', (tester) async {
    final lock = AppLockController(storage: MemoryLockStorage(), iterations: 1000);
    await tester.runAsync(lock.load);
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.light),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(onPressed: () => openLockSetup(context, lock, LockType.pattern), child: const Text('開始')),
        ),
      ),
    ));
    await tester.tap(find.text('開始'));
    await tester.pumpAndSettle();
    expect(find.text('畫出新的解鎖圖形'), findsOneWidget);

    // 依序拖過幾個點（0–8，左上到右下）
    Future<void> draw(List<int> dots) async {
      final pad = tester.getRect(find.byType(PatternPad));
      Offset at(int dot) => pad.topLeft + Offset((dot % 3 + 0.5) * pad.width / 3, (dot ~/ 3 + 0.5) * pad.height / 3);
      final gesture = await tester.startGesture(at(dots.first));
      for (final dot in dots.skip(1)) {
        await gesture.moveTo(at(dot));
        await tester.pump();
      }
      await gesture.up();
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
      await tester.pumpAndSettle();
    }

    await draw([0, 1, 2]);
    expect(find.text('至少連接 4 個點'), findsOneWidget);
    await draw([0, 1, 2, 5]);
    expect(find.text('再畫一次圖形'), findsOneWidget);
    await draw([0, 3, 6, 7]);
    expect(find.text('兩次不一樣，請重新設定'), findsOneWidget);
    expect(lock.enabled, isFalse);

    // 0 → 2 會自動補上中間的 1
    await draw([0, 2, 5, 8]);
    await draw([0, 1, 2, 5, 8]);
    expect(lock.enabled, isTrue);
    expect(lock.type, LockType.pattern);
    expect(find.text('開始'), findsOneWidget);
    await tester.runAsync(() async {
      expect((await lock.verify('0-1-2-5-8')) is LockCheckOk, isTrue);
    });
  });
}
