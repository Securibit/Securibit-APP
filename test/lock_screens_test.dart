import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:securibit/core/theme/app_theme.dart';
import 'package:securibit/core/widgets/lock_backdrop.dart';
import 'package:securibit/features/auth/profile.dart';
import 'package:securibit/features/groups/group_models.dart';
import 'package:securibit/features/settings/lock/app_lock_controller.dart';
import 'package:securibit/features/settings/lock/lock_screen.dart';
import 'package:securibit/features/settings/lock/lock_secret.dart';
import 'package:securibit/features/vault/vault_controller.dart';
import 'package:securibit/features/vault/vault_info.dart';
import 'package:securibit/features/vault/vault_unlock_view.dart';

import 'app_lock_test.dart' show MemoryLockStorage;

// 兩個鎖定畫面（App 鎖定、加密群組解鎖）：亮色深色、手機與桌面大小都放得下標題與底部署名，不會超出畫面
void main() {
  const sizes = {'手機': Size(390, 844), '小手機': Size(320, 568), '桌面': Size(1180, 748)};

  Future<void> setSize(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  void expectChrome(WidgetTester tester) {
    expect(tester.takeException(), isNull);
    expect(find.text('解鎖'), findsWidgets);
    expect(find.text('Securibit'), findsOneWidget);
    expect(find.text('幣友 BITYO 出品'), findsOneWidget);
    expect(find.byType(LockBackdrop), findsOneWidget);
  }

  for (final brightness in Brightness.values) {
    for (final MapEntry(key: name, value: size) in sizes.entries) {
      testWidgets('App 鎖定畫面：${brightness.name}、$name', (tester) async {
        await setSize(tester, size);
        final lock = AppLockController(storage: MemoryLockStorage(), iterations: 1000);
        await tester.runAsync(() => lock.setLock(LockType.pin6, '123456'));
        await tester.pumpWidget(MaterialApp(
          theme: buildTheme(brightness),
          home: LockScreen(lock: lock, onUnlocked: () {}),
        ));
        await tester.pump();
        expectChrome(tester);
        expect(find.text('輸入 6 位數密碼'), findsOneWidget);
        expect(find.text('忘記密碼'), findsOneWidget);
        // 署名在畫面最下方、標題之下
        expect(tester.getRect(find.text('幣友 BITYO 出品')).bottom, lessThanOrEqualTo(size.height));
        expect(tester.getTopLeft(find.text('幣友 BITYO 出品')).dy, greaterThan(tester.getTopLeft(find.text('Securibit')).dy));
      });

      testWidgets('加密群組解鎖畫面：${brightness.name}、$name', (tester) async {
        await setSize(tester, size);
        final info = VaultInfo.fromJson({'v': 1, 'salt': 'LFyhBkLr6c+SV0KV3AoamA==', 'iterations': 600000, 'check': 'enc:v1:AAAA:BBBB'})!;
        final vault = VaultController()
          ..attach(Profile(uid: 'u1', name: '測試', username: '', email: 'a@b.c', photoUrl: '', vault: info, defaultGroupId: null));
        const group = GroupSummary(
          id: 'g1',
          name: '加密群組',
          description: '',
          ownerId: 'u1',
          isOwner: true,
          isDefault: false,
          encrypted: true,
          position: 0,
          memberCount: 1,
          accountCount: 0,
          permissions: 0,
        );
        await tester.pumpWidget(ChangeNotifierProvider.value(
          value: vault,
          child: MaterialApp(
            theme: buildTheme(brightness),
            home: const Scaffold(body: LockBackdrop(child: VaultUnlockView(group: group))),
          ),
        ));
        // 讀不到這台裝置記住的金鑰（測試沒有安全儲存）就是鎖定中
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
        await tester.pump();
        expect(vault.status, VaultStatus.locked);
        expectChrome(tester);
        expect(find.text('輸入你設定的加密密碼來解鎖加密群組'), findsOneWidget);
        expect(find.text('在這台裝置記住'), findsOneWidget);
        expect(find.text('忘記密碼？'), findsOneWidget);
        expect(tester.getRect(find.text('幣友 BITYO 出品')).bottom, lessThanOrEqualTo(size.height));

        // 眼睛切換顯示密碼
        expect(tester.widget<TextField>(find.byType(TextField)).obscureText, isTrue);
        await tester.tap(find.byTooltip('顯示密碼'));
        await tester.pump();
        expect(tester.widget<TextField>(find.byType(TextField)).obscureText, isFalse);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
