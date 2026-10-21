import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:securibit/core/theme/app_theme.dart';
import 'package:securibit/features/auth/profile.dart';
import 'package:securibit/features/cache/offline_cache.dart';
import 'package:securibit/features/groups/groups_controller.dart';
import 'package:securibit/features/vault/vault_controller.dart';
import 'package:securibit/features/vault/vault_info.dart';
import 'package:securibit/features/vault/vault_settings_section.dart';
import 'package:securibit/src/rust/api/secrets.dart';
import 'package:securibit/src/rust/api/vault.dart';

/*
 * 設定、更改、停用加密密碼：新金鑰在 Rust 產生、存到伺服器前不生效（完整的伺服器流程在 rust/api 的 cargo test），
 * 以及設定頁「加密」區塊在各狀態顯示的動作。
 */
const _connection = SupabaseConnection(url: 'http://127.0.0.1:9', anonKey: 'anon', accessToken: 'token', userAgent: 'test');

Profile _profile(VaultInfo? vault) =>
    Profile(uid: 'u1', name: '測試', username: '', email: 'a@b.c', photoUrl: '', vault: vault, defaultGroupId: null);

void main() {
  test('新的加密設定格式同網站，存到伺服器前不生效', () async {
    vaultLock();
    final setup = await vaultCreate(passphrase: '新的密碼 abcdefgh');
    expect(setup.iterations, 600000);
    expect(base64.decode(setup.salt).length, 16);
    expect(setup.check, startsWith('enc:v1:'));
    expect(vaultIsUnlocked(), isFalse);

    // 用網站同一套 unlock 解得開
    final result = await vaultUnlock(salt: setup.salt, iterations: setup.iterations, check: setup.check, passphrase: '新的密碼 abcdefgh');
    expect(result, VaultUnlockResult.unlocked);

    // 鎖定時暫存的新設定一起丟掉
    await vaultCreate(passphrase: '另一組密碼 12345678');
    vaultLock();
    expect(
      await vaultRewriteAll(connection: _connection, usePending: true, expectedCheck: setup.check),
      '新的加密設定已失效，請再試一次',
    );
    expect(await vaultRewriteAll(connection: _connection, usePending: false), '尚未啟用加密');
    expect(
      await vaultSetGroupEncrypted(connection: _connection, gid: 'g', encrypted: true, expectedCheck: setup.check),
      '請先輸入加密密碼解鎖',
    );
  }, timeout: const Timeout(Duration(minutes: 2)));

  Future<VaultController> pumpSection(WidgetTester tester, VaultInfo? info) async {
    final vault = VaultController()..attach(_profile(info));
    final groups = GroupsController(cache: const OfflineCache());
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: vault),
        ChangeNotifierProvider.value(value: groups),
      ],
      child: MaterialApp(
        theme: buildTheme(Brightness.light),
        home: const Scaffold(body: SingleChildScrollView(child: VaultSettingsSection())),
      ),
    ));
    return vault;
  }

  testWidgets('未設定：設定密碼要至少 8 個字、兩次一樣並勾選了解', (tester) async {
    await pumpSection(tester, null);
    expect(find.text('未設定'), findsOneWidget);
    expect(find.text('已加密的群組'), findsNothing);

    await tester.tap(find.text('設定加密密碼'));
    await tester.pumpAndSettle();
    TextButton submit() => tester.widget<TextButton>(find.widgetWithText(TextButton, '啟用'));
    expect(submit().onPressed, isNull);

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'short');
    await tester.pump();
    expect(find.text('至少 8 個字元'), findsOneWidget);

    await tester.enterText(fields.at(0), 'long enough');
    await tester.enterText(fields.at(1), 'different!');
    await tester.pump();
    expect(find.text('兩次輸入的密碼不一樣'), findsOneWidget);

    await tester.enterText(fields.at(1), 'long enough');
    await tester.pump();
    expect(submit().onPressed, isNull, reason: '還沒勾選「我了解」');
    await tester.tap(find.text('我了解忘記密碼就無法救回金鑰，只能清空重新綁定'));
    await tester.pump();
    expect(submit().onPressed, isNotNull);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.text('設定加密密碼'), findsOneWidget);
  });

  testWidgets('鎖定中：可以解鎖或忘記密碼（確認對話框照網站的文字）', (tester) async {
    final info = VaultInfo.fromJson({'v': 1, 'salt': 'LFyhBkLr6c+SV0KV3AoamA==', 'iterations': 600000, 'check': 'enc:v1:AAAA:BBBB'})!;
    await pumpSection(tester, info);
    // 讀不到這台裝置記住的金鑰（測試沒有安全儲存）就是鎖定中
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump();
    expect(find.text('已設定，鎖定中'), findsOneWidget);
    expect(find.text('解鎖'), findsOneWidget);
    expect(find.text('更改密碼'), findsNothing);

    await tester.tap(find.text('忘記密碼'));
    await tester.pumpAndSettle();
    expect(find.textContaining('密碼沒有辦法找回，也沒有人能幫你解開'), findsOneWidget);
    expect(find.text('清空並停用加密'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.text('已設定，鎖定中'), findsOneWidget);
  });
}
