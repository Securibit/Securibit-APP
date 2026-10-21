import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:securibit/core/permissions.dart';
import 'package:securibit/core/result.dart';
import 'package:securibit/core/theme/app_theme.dart';
import 'package:securibit/features/cache/offline_cache.dart';
import 'package:securibit/features/codes/code_models.dart';
import 'package:securibit/features/codes/codes_controller.dart';
import 'package:securibit/features/codes/totp/import_text.dart';
import 'package:securibit/features/codes/totp/totp_params.dart';
import 'package:securibit/features/codes/transfer/bulk_import_page.dart';
import 'package:securibit/features/codes/transfer/duplicates.dart';
import 'package:securibit/features/codes/transfer/export_data.dart';
import 'package:securibit/features/codes/transfer/export_pages.dart';
import 'package:securibit/features/codes/transfer/import_repository.dart';
import 'package:securibit/features/codes/widgets/code_form.dart';
import 'package:securibit/features/groups/group_models.dart';

// 整批匯入送出的內容、金鑰重複的檢查、匯出的備份檔，以及匯入／匯出畫面

GroupAccount account(String id, String name, {int period = 30}) => GroupAccount(
      id: id,
      name: name,
      category: '',
      digits: 6,
      period: period,
      algorithm: TotpAlgorithm.sha1,
      pinned: false,
      permissions: GroupPermission.viewSecrets,
      hasOverwrites: false,
    );

// 不會連線的 controller：加密群組而且不是擁有者，一建立就是鎖定，不會讀取
CodesController offlineController() => CodesController(
      group: const GroupSummary(
        id: 'g1',
        name: '我的驗證碼',
        description: '',
        ownerId: 'other',
        isOwner: false,
        isDefault: true,
        encrypted: true,
        position: 0,
        memberCount: 1,
        accountCount: 0,
        permissions: GroupPermission.manageCodes,
      ),
      uid: 'u1',
      vaultKeyId: null,
      cache: const OfflineCache(),
    );

Widget app(Widget child) => MaterialApp(theme: buildTheme(Brightness.light), home: child);

void main() {
  group('整批匯入送出的內容', () {
    const inputs = [
      TotpInput(name: '  GitHub - me  ', secret: 'jbsw y3dp-ehpk 3pxp', category: '工作， 個人'),
      TotpInput(name: 'Acme', secret: 'MZXW6YTBOI', digits: 8, period: 60, algorithm: TotpAlgorithm.sha512),
    ];

    test('名稱去空白、金鑰正規化、類別整理', () {
      final items = buildImportItems(inputs, encrypted: false).dataOrNull!;
      expect(items[0], {
        'name': 'GitHub - me',
        'secret': 'JBSWY3DPEHPK3PXP',
        'category': '工作,個人',
        'digits': 6,
        'period': 30,
        'algorithm': 'SHA-1',
      });
      expect(items[1]['digits'], 8);
      expect(items[1]['period'], 60);
      expect(items[1]['algorithm'], 'SHA-512');
      expect(items[1]['category'], '');
    });

    test('統一指定的類別取代各筆原本的，留空則保留', () {
      final items = buildImportItems(inputs, category: '家裡、 工作', encrypted: false).dataOrNull!;
      expect(items.map((i) => i['category']), ['家裡,工作', '家裡,工作']);
      final kept = buildImportItems(inputs, category: ' ， ', encrypted: false).dataOrNull!;
      expect(kept.map((i) => i['category']), ['工作,個人', '']);
    });

    test('加密群組逐筆加密正規化後的金鑰', () {
      final seen = <String>[];
      final items = buildImportItems(inputs, encrypted: true, encrypt: (secret) {
        seen.add(secret);
        return 'enc:v1:$secret';
      }).dataOrNull!;
      expect(seen, ['JBSWY3DPEHPK3PXP', 'MZXW6YTBOI']);
      expect(items.map((i) => i['secret']), ['enc:v1:JBSWY3DPEHPK3PXP', 'enc:v1:MZXW6YTBOI']);
    });

    test('沒加密的群組不加密', () {
      final items = buildImportItems(inputs, encrypted: false, encrypt: (_) => throw StateError('不該加密')).dataOrNull!;
      expect(items.first['secret'], 'JBSWY3DPEHPK3PXP');
    });

    test('加密群組已鎖定時整批不送', () {
      final result = buildImportItems(inputs, encrypted: true, encrypt: (_) => null);
      expect(result.messageOrNull, vaultLockedMessage);
    });

    test('沒有勾選任何一筆時不呼叫伺服器', () async {
      final result = await importGroupAccounts('g1', const [], encrypted: false);
      expect(result, isA<Ok<List<String>>>());
      expect(result.dataOrNull, isEmpty);
    });
  });

  group('金鑰重複', () {
    final accounts = [account('a', 'A'), account('b', 'B'), account('c', 'C')];
    final secrets = {'a': 'JBSWY3DPEHPK3PXP', 'b': null, 'c': 'MZXW6YTBOI'};

    test('找出相同金鑰的那一筆（比對前正規化）', () {
      expect(findDuplicate(accounts, (a) => secrets[a.id], 'mzxw 6ytb-oi==')?.id, 'c');
      expect(findDuplicate(accounts, (a) => secrets[a.id], 'GEZDGNBVGY3TQOJQ'), isNull);
      // 看不到金鑰的不算
      expect(findDuplicate(accounts, (_) => null, 'JBSWY3DPEHPK3PXP'), isNull);
      expect(findDuplicate(accounts, (a) => secrets[a.id], '  '), isNull);
    });

    test('整批匯入：和既有的或清單裡前面的重複', () {
      final marks = markDuplicates(
        ['JBSWY3DPEHPK3PXP'],
        const [
          TotpInput(name: '1', secret: 'jbswy3dpehpk3pxp'),
          TotpInput(name: '2', secret: 'MZXW6YTBOI'),
          TotpInput(name: '3', secret: 'mzxw6ytboi'),
          TotpInput(name: '4', secret: 'GEZDGNBVGY3TQOJQ'),
        ],
      );
      expect(marks, [true, false, true, false]);
    });
  });

  group('匯出', () {
    test('備份檔：註解兩行，接著每行一個連結', () {
      final now = DateTime(2026, 3, 7, 9, 5);
      final text = buildBackupText(const [
        TotpInput(name: 'A B', secret: 'JBSWY3DPEHPK3PXP', category: '工作'),
        TotpInput(name: 'C', secret: 'MZXW6YTBOI', digits: 8, period: 60, algorithm: TotpAlgorithm.sha256),
      ], now);
      expect(text.split('\n'), [
        '# Securibit TOTP 備份（2026/03/07 09:05，共 2 筆）',
        '# 每行一個 otpauth:// 連結，可匯入本站或其他支援的驗證器 App',
        'otpauth://totp/A%20B?secret=JBSWY3DPEHPK3PXP&algorithm=SHA1&digits=6&period=30&category=%E5%B7%A5%E4%BD%9C',
        'otpauth://totp/C?secret=MZXW6YTBOI&algorithm=SHA256&digits=8&period=60',
      ]);
      expect(backupFileName(now), 'securibit-totp-20260307.txt');

      // 備份檔可以再整批匯入回來
      final back = parseImportText(text);
      expect(back.errors, isEmpty);
      expect(back.items.map((i) => i.name), ['A B', 'C']);
      expect(back.items.first.category, '工作');
      expect(back.items.last.period, 60);
    });

    test('匯出的內容用清單上的設定', () {
      final item = exportInput(account('x', 'X', period: 60), 'JBSWY3DPEHPK3PXP');
      expect(item.period, 60);
      expect(item.secret, 'JBSWY3DPEHPK3PXP');
    });

    test('沒有「查看金鑰」的不匯出', () {
      final controller = offlineController();
      addTearDown(controller.dispose);
      controller.accounts = [account('a', 'A'), account('b', 'B')];
      final result = exportableItems(controller);
      expect(result.items, isEmpty);
      expect(result.missing, 2);
    });

    test('一筆的補充說明', () {
      expect(describeImportItem(const TotpInput(name: 'a', secret: 'A')), '');
      expect(
        describeImportItem(const TotpInput(name: 'a', secret: 'A', category: '工作,個人', digits: 8, period: 60, algorithm: TotpAlgorithm.sha256)),
        '工作、個人 · 8 位數 · 60 秒 · SHA-256',
      );
    });
  });

  group('畫面', () {
    testWidgets('整批匯入：可以取消勾選，按鈕跟著顯示筆數，也列出無法匯入的', (tester) async {
      final controller = offlineController();
      addTearDown(controller.dispose);
      final result = ImportTextResult(
        items: const [
          TotpInput(name: 'GitHub - me', secret: 'JBSWY3DPEHPK3PXP'),
          TotpInput(name: 'Acme', secret: 'MZXW6YTBOI', digits: 8),
        ],
        errors: ['略過 1 筆 HOTP（計數型）驗證碼'],
      );
      await tester.pumpWidget(app(BulkImportPage(controller: controller, result: result)));

      expect(find.text('匯入 2 筆驗證碼'), findsOneWidget);
      expect(find.text('匯入 2 筆'), findsOneWidget);
      expect(find.text('8 位數'), findsOneWidget);
      expect(find.text('以下內容無法匯入'), findsOneWidget);
      expect(find.text('・略過 1 筆 HOTP（計數型）驗證碼'), findsOneWidget);

      await tester.tap(find.text('Acme'));
      await tester.pump();
      expect(find.text('匯入 1 筆'), findsOneWidget);

      await tester.tap(find.text('GitHub - me'));
      await tester.pump();
      final button = tester.widget<FilledButton>(find.widgetWithText(FilledButton, '匯入 0 筆'));
      expect(button.onPressed, isNull);
    });

    testWidgets('整批匯入：分批的 Google Authenticator 匯出提醒繼續掃下一張', (tester) async {
      final controller = offlineController();
      addTearDown(controller.dispose);
      final result = parseImportText(
        'otpauth-migration://offline?data=Ci0KCkhlbGxvId6tvu8SEWFsaWNlQGV4YW1wbGUuY29tGgZHaXRIdWIgASgBMAIQARgCIAAoBw%3D%3D',
      );
      expect(result.batch?.size, 2);
      await tester.pumpWidget(app(BulkImportPage(controller: controller, result: result)));
      expect(find.text('第 1 / 2 張匯出 QR Code'), findsOneWidget);
      expect(find.text('這是第 1 / 2 張，匯入後請繼續掃描下一張'), findsOneWidget);
      expect(find.text('GitHub - alice@example.com'), findsOneWidget);
    });

    testWidgets('全部匯出：有安全提醒，分批 QR 可以翻頁，30 秒以外的提示改用文字備份', (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final items = [
        for (var i = 0; i < 12; i++) TotpInput(name: 'Item $i', secret: 'JBSWY3DPEHPK3PXP'),
        const TotpInput(name: 'Sixty', secret: 'MZXW6YTBOI', period: 60),
      ];
      await tester.pumpWidget(app(ExportAllPage(items: items, missing: 3)));

      expect(find.text('共 13 筆'), findsOneWidget);
      expect(find.textContaining('裡面包含金鑰'), findsOneWidget);
      expect(find.text('有 3 筆你沒有「查看金鑰」權限（或金鑰錯誤），不會匯出'), findsOneWidget);
      expect(find.text('1 / 2'), findsOneWidget);
      expect(find.text('有 1 筆不是 30 秒週期，Google Authenticator 不支援，請改用文字備份'), findsOneWidget);

      await tester.tap(find.byTooltip('下一張'));
      await tester.pump();
      expect(find.text('2 / 2'), findsOneWidget);

      await tester.tap(find.text('文字備份'));
      await tester.pumpAndSettle();
      expect(find.text('複製全部連結'), findsOneWidget);
    });

    testWidgets('單筆匯出：QR Code、安全提醒與複製連結', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(app(const ExportItemPage(item: TotpInput(name: 'GitHub', secret: 'JBSWY3DPEHPK3PXP'))));
      expect(find.text('匯出「GitHub」'), findsOneWidget);
      expect(find.textContaining('裡面包含金鑰'), findsOneWidget);
      expect(find.text('複製連結'), findsOneWidget);
    });

    testWidgets('新增表單：一個連結填好欄位，多筆開整批匯入', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final controller = offlineController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(app(CodeForm(controller: controller)));

      final link = find.widgetWithText(TextField, '貼上 otpauth 連結');
      await tester.enterText(link, 'otpauth://totp/GitHub:me?secret=jbswy3dpehpk3pxp&issuer=GitHub');
      await tester.pump();
      expect(find.text('GitHub - me'), findsOneWidget);

      // Google Authenticator 的匯出連結以前要到網站匯入，現在直接開整批匯入
      await tester.enterText(
        link,
        'otpauth-migration://offline?data=Ci0KCkhlbGxvId6tvu8SEWFsaWNlQGV4YW1wbGUuY29tGgZHaXRIdWIgASgBMAIQARgCIAAoBw%3D%3D',
      );
      await tester.pumpAndSettle();
      expect(find.text('匯入 1 筆驗證碼'), findsOneWidget);
      expect(find.text('GitHub - alice@example.com'), findsOneWidget);

      // 整批匯入疊在表單上面，關掉後回到表單
      await tester.tap(find.text('取消').last);
      await tester.pumpAndSettle();
      expect(find.text('匯入 1 筆驗證碼'), findsNothing);
      expect(find.text('新增驗證碼'), findsOneWidget);
    });

    testWidgets('新增表單：解析失敗時顯示原因', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final controller = offlineController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(app(CodeForm(controller: controller)));
      await tester.enterText(find.widgetWithText(TextField, '貼上 otpauth 連結'), 'otpauth://hotp/a?secret=JBSWY3DP');
      await tester.pump();
      expect(find.text('目前只支援 TOTP（時間型）驗證碼，不支援 HOTP（計數型）'), findsOneWidget);
    });
  });
}
