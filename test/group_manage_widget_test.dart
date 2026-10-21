import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:securibit/core/theme/app_theme.dart';
import 'package:securibit/features/admin/admin_models.dart';
import 'package:securibit/features/admin/hierarchy.dart';
import 'package:securibit/features/groups/manage/group_forms.dart';
import 'package:securibit/features/groups/manage/group_invites_tab.dart';
import 'package:securibit/features/groups/manage/group_members_tab.dart';
import 'package:securibit/features/groups/manage/group_settings_tab.dart';
import 'package:securibit/features/groups/manage/group_tab_context.dart';
import 'package:securibit/features/vault/vault_controller.dart';

import 'group_manage_test.dart' show detailJson, member;

// 群組管理的分頁：依權限顯示的內容與擋住的動作（不呼叫 RPC，只看畫面）
void main() {
  GroupTabContext tabOf(AdminGroupDetail detail, {String? myUid = 'u1'}) => GroupTabContext(
        detail: detail,
        actor: Actor(unrestricted: detail.isOwner, topPosition: detail.topPosition),
        myUid: myUid,
        adminMode: false,
        onChanged: () async {},
        onExit: () {},
        onOpenUser: (_) {},
      );

  Future<void> pump(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ChangeNotifierProvider(
      create: (_) => VaultController(),
      child: MaterialApp(
        theme: buildTheme(Brightness.light),
        home: Scaffold(body: ListView(padding: const EdgeInsets.all(16), children: [child])),
      ),
    ));
  }

  testWidgets('邀請分頁：建立連結、有效的連結與等待回覆的邀請', (tester) async {
    await pump(tester, GroupInvitesTab(tab: tabOf(AdminGroupDetail.fromJson(detailJson()))));
    expect(find.text('建立連結'), findsOneWidget);
    expect(find.text('7 天'), findsOneWidget);
    expect(find.text('不限次數'), findsOneWidget);
    expect(find.textContaining('/invite/AbCdEfGh_-123456'), findsOneWidget);
    expect(find.text('bob@example.com'), findsOneWidget);
    // 自己建立的與管理群組都能撤銷
    expect(find.byTooltip('撤銷'), findsNWidgets(2));
  });

  testWidgets('邀請分頁：沒有邀請成員只看得到清單，別人的連結不能撤銷', (tester) async {
    // 只有管理群組以外的基本權限，邀請由別人建立
    final json = detailJson(isOwner: false, permissions: 2);
    await pump(tester, GroupInvitesTab(tab: tabOf(AdminGroupDetail.fromJson(json), myUid: 'u9')));
    expect(find.text('建立連結'), findsNothing);
    expect(find.byTooltip('撤銷'), findsNothing);
    expect(find.text('取消'), findsNothing);
  });

  testWidgets('設定分頁：擁有者的預設群組不能刪除，轉移照規則', (tester) async {
    final detail = AdminGroupDetail.fromJson(detailJson(isDefault: true, ownedCount: 1));
    await pump(tester, GroupSettingsTab(tab: tabOf(detail)));
    expect(find.text('預設與加密'), findsOneWidget);
    expect(find.text('目前的預設'), findsOneWidget);
    // 沒設定加密密碼時引導去設定
    expect(find.text('先設定加密密碼'), findsOneWidget);
    expect(find.text('刪除群組'), findsOneWidget);
    expect(find.text('離開群組'), findsNothing);
    expect(find.textContaining('唯一擁有的群組，要先建立另一個群組才能轉移'), findsOneWidget);
  });

  testWidgets('設定分頁：一般成員可以離開，看不到預設與加密', (tester) async {
    final json = detailJson(isOwner: false, permissions: 2, members: [member('u1', 'Owner', owner: true), member('u2', 'Me')]);
    await pump(tester, GroupSettingsTab(tab: tabOf(AdminGroupDetail.fromJson(json), myUid: 'u2')));
    expect(find.text('預設與加密'), findsNothing);
    expect(find.text('離開群組'), findsOneWidget);
    expect(find.text('刪除群組'), findsNothing);
    expect(find.text('需要「管理群組」權限才能修改名稱與說明'), findsOneWidget);
  });

  testWidgets('成員分頁：擁有者排第一，可以管理別人', (tester) async {
    final json = detailJson(members: [member('u2', 'Bob'), member('u1', 'Andy', owner: true)]);
    await pump(tester, GroupMembersTab(tab: tabOf(AdminGroupDetail.fromJson(json))));
    expect(find.text('共 2 位成員'), findsOneWidget);
    expect(find.text('擁有者'), findsOneWidget);
    expect(find.text('你'), findsOneWidget);
    // 只有 Bob 那一列有「更多」
    expect(find.byTooltip('更多'), findsOneWidget);
    expect(tester.getTopLeft(find.text('Andy')).dy, lessThan(tester.getTopLeft(find.text('Bob')).dy));
  });

  testWidgets('轉移擁有權：要先選一位成員', (tester) async {
    final detail = AdminGroupDetail.fromJson(detailJson(members: [member('u1', 'Andy', owner: true), member('u2', 'Bob')]));
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.light),
      home: GroupTransferForm(groupId: 'g1', candidates: detail.members.where((m) => !m.isOwner).toList()),
    ));
    TextButton submit() => tester.widget<TextButton>(find.widgetWithText(TextButton, '轉移'));
    expect(submit().onPressed, isNull);
    await tester.tap(find.text('Bob'));
    await tester.pump();
    expect(submit().onPressed, isNotNull);
  });
}
