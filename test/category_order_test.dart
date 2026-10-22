import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:securibit/core/theme/app_theme.dart';
import 'package:securibit/core/permissions.dart';
import 'package:securibit/features/admin/admin_models.dart';
import 'package:securibit/features/admin/audit_text.dart';
import 'package:securibit/features/cache/offline_cache.dart';
import 'package:securibit/features/codes/code_models.dart';
import 'package:securibit/features/codes/codes_controller.dart';
import 'package:securibit/features/codes/totp/categories.dart';
import 'package:securibit/features/codes/totp/totp_params.dart';
import 'package:securibit/features/codes/widgets/category_order_editor.dart';
import 'package:securibit/features/groups/group_models.dart';

GroupAccount account(String id, String category) => GroupAccount(
      id: id,
      name: id,
      category: category,
      digits: 6,
      period: 30,
      algorithm: TotpAlgorithm.sha1,
      pinned: false,
      permissions: 0,
      hasOverwrites: false,
    );

// 加密群組、不是擁有者：鎖定中，不會連線讀取
CodesController controllerOf(int permissions) => CodesController(
      group: GroupSummary(
        id: 'g',
        name: 'g',
        description: '',
        ownerId: 'owner',
        isOwner: false,
        isDefault: false,
        encrypted: true,
        position: 0,
        memberCount: 3,
        accountCount: 0,
        permissions: permissions,
      ),
      uid: 'u',
      vaultKeyId: null,
      cache: const OfflineCache(),
    );

// 群組的類別自訂順序（group_detail 的 category_order、group_set_category_order）
void main() {
  group('orderCategories', () {
    test('存過的照順序排前面，其餘照字母排在後面', () {
      expect(orderCategories(['a', 'b', 'c', 'd'], ['c', 'a']), ['c', 'a', 'b', 'd']);
    });

    test('存過但已經沒有的類別不列出', () {
      expect(orderCategories(['工作', '個人'], ['已刪除', '個人']), ['個人', '工作']);
    });

    test('沒排過就全部照字母排；沒有類別就是空的', () {
      expect(orderCategories(['b', 'a'], const []), ['a', 'b']);
      expect(orderCategories(const [], ['a']), isEmpty);
    });

    test('重複的名稱只算一次', () {
      expect(orderCategories(['a', 'b', 'a'], ['b', 'b']), ['b', 'a']);
    });
  });

  group('parseCategoryOrder', () {
    test('不是陣列（舊的資料庫沒有這個欄位）就是空的', () {
      expect(parseCategoryOrder(null), isEmpty);
      expect(parseCategoryOrder('a,b'), isEmpty);
      expect(parseCategoryOrder({'a': 1}), isEmpty);
    });

    test('只留非空字串，去頭尾空白、去重，保留原本順序', () {
      expect(parseCategoryOrder([' 工作 ', 3, null, '', '個人', '工作']), ['工作', '個人']);
    });

    test('group_detail 解析出 categoryOrder，沒有欄位時是空的', () {
      expect(AdminGroupDetail.fromJson({'category_order': ['b', 'a']}).categoryOrder, ['b', 'a']);
      expect(AdminGroupDetail.fromJson({'group': {'id': 'g'}}).categoryOrder, isEmpty);
      expect(AdminGroupDetail.fromJson(null).categoryOrder, isEmpty);
    });
  });

  group('CodesController', () {
    test('篩選與建議清單的類別照群組的順序', () {
      final controller = controllerOf(GroupPermission.manageCodes);
      addTearDown(controller.dispose);
      controller.accounts = [account('1', '工作,個人'), account('2', '銀行'), account('3', 'a')];
      expect(controller.categories, ['a', '個人', '工作', '銀行']);
      controller.categoryOrder = ['銀行', '不存在', '工作'];
      expect(controller.categories, ['銀行', '工作', 'a', '個人']);
    });

    test('調整類別順序要「管理驗證碼」、兩個以上的類別，離線時不行', () {
      final viewer = controllerOf(GroupPermission.viewCodes);
      addTearDown(viewer.dispose);
      viewer.accounts = [account('1', 'a,b')];
      expect(viewer.canSortCategories, isFalse);

      final manager = controllerOf(GroupPermission.manageCodes);
      addTearDown(manager.dispose);
      manager.accounts = [account('1', 'a'), account('2', 'a')];
      expect(manager.canSortCategories, isFalse, reason: '只有一個類別沒有順序可以調');
      manager.accounts = [account('1', 'a'), account('2', 'b')];
      expect(manager.canSortCategories, isTrue);
      manager.offline = true;
      expect(manager.canSortCategories, isFalse);
    });
  });

  test('操作紀錄的說明', () {
    expect(auditActionText('group.category.reorder'), '調整類別順序');
  });

  testWidgets('調整類別順序的對話框：箭頭移動後才能儲存，取消不保留', (tester) async {
    final controller = controllerOf(GroupPermission.manageCodes);
    addTearDown(controller.dispose);
    controller.accounts = [account('1', '工作,個人'), account('2', '銀行')];
    controller.categoryOrder = ['銀行'];
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.light),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(onPressed: () => showCategoryOrderEditor(context, controller), child: const Text('打開')),
        ),
      ),
    ));
    await tester.tap(find.text('打開'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    List<String> shown() => tester.widgetList<Text>(find.descendant(of: find.byType(ReorderableListView), matching: find.byType(Text))).map((t) => t.data!).toList();
    expect(shown(), ['銀行', '個人', '工作']);
    TextButton save() => tester.widget<TextButton>(find.widgetWithText(TextButton, '儲存'));
    expect(save().onPressed, isNull, reason: '沒有變動不用儲存');

    await tester.tap(find.byTooltip('往下移').first);
    await tester.pump();
    expect(shown(), ['個人', '銀行', '工作']);
    expect(save().onPressed, isNotNull);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.byType(CategoryOrderEditor), findsNothing);
    expect(controller.categories, ['銀行', '個人', '工作']);
  });
}
