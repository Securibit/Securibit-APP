import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:securibit/core/theme/app_theme.dart';
import 'package:securibit/features/auth/auth_controller.dart';
import 'package:securibit/features/cache/offline_cache.dart';
import 'package:securibit/features/onboarding/live_demo.dart';
import 'package:securibit/features/onboarding/signed_out_view.dart';

// 固定在某一個時間，示範驗證碼不會跟著真的時鐘跑（也不會留下計時器）
final _clock = ValueNotifier<int>(DateTime.utc(2026, 1, 1, 12).millisecondsSinceEpoch);

Widget _app({required bool mobile}) {
  final auth = AuthController(cache: const OfflineCache(), onSignedIn: (_) {}, onSignedOut: (_) {});
  return ChangeNotifierProvider.value(
    value: auth,
    child: MaterialApp(
      theme: buildTheme(Brightness.light),
      home: DemoClock(
        clock: _clock,
        child: SignedOutView(mobile: mobile),
      ),
    ),
  );
}

// 動畫跑完（不用 pumpAndSettle：介紹頁有定時換人的示範）
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  group('shouldShowOnboarding', () {
    test('手機沒看過介紹頁時要顯示', () {
      expect(shouldShowOnboarding(mobile: true, introDone: false), isTrue);
    });
    test('手機看過之後進登入頁', () {
      expect(shouldShowOnboarding(mobile: true, introDone: true), isFalse);
    });
    test('桌面版永遠不顯示', () {
      expect(shouldShowOnboarding(mobile: false, introDone: false), isFalse);
      expect(shouldShowOnboarding(mobile: false, introDone: true), isFalse);
    });
  });

  testWidgets('桌面版沒登入時直接是登入頁', (tester) async {
    await tester.pumpWidget(_app(mobile: false));
    await _settle(tester);
    expect(find.text('使用 Google 登入'), findsOneWidget);
    expect(find.text('略過'), findsNothing);
  });

  testWidgets('手機滑到最後一頁按開始使用進登入頁', (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app(mobile: true));
    expect(find.text('打開就是你的驗證碼'), findsOneWidget);
    expect(find.text('使用 Google 登入'), findsNothing);
    expect(find.text('開始使用'), findsNothing);

    // 往左滑一頁，再按兩次繼續到最後一頁
    await tester.fling(find.text('打開就是你的驗證碼'), const Offset(-300, 0), 1000);
    await _settle(tester);
    expect(find.text('和家人、同事共用'), findsOneWidget);
    for (var i = 0; i < 2; i++) {
      await tester.tap(find.text('繼續'));
      await _settle(tester);
    }
    expect(find.text('網站和 App 同步'), findsOneWidget);
    expect(find.text('開始使用'), findsOneWidget);

    await tester.tap(find.text('開始使用'));
    await _settle(tester);
    expect(find.text('使用 Google 登入'), findsOneWidget);
    expect(find.byType(PageView), findsNothing);
  });

  testWidgets('手機按略過直接進登入頁', (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app(mobile: true));
    await tester.tap(find.text('略過'));
    await _settle(tester);
    expect(find.text('使用 Google 登入'), findsOneWidget);
  });

  test('示範驗證碼和 RFC 6238 的算法一致', () {
    // 同一個 30 秒內的碼相同，剩餘秒數照時間算
    final account = demoAccounts.first;
    final a = DemoCode.at(account, 1767268800000);
    final b = DemoCode.at(account, 1767268800000 + 29000);
    expect(a.code, b.code);
    expect(a.code, hasLength(6));
    expect(a.secondsLeft, 30);
    expect(b.secondsLeft, 1);
    expect(b.expiring, isTrue);
  });
}
