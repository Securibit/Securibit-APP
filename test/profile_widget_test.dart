import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:securibit/core/theme/app_theme.dart';
import 'package:securibit/features/auth/auth_controller.dart';
import 'package:securibit/features/auth/profile.dart';
import 'package:securibit/features/cache/offline_cache.dart';
import 'package:securibit/features/profile/account_section.dart';
import 'package:securibit/features/profile/profile_edit_form.dart';
import 'package:securibit/features/profile/username_form.dart';

/*
 * 設定頁的帳戶區塊、編輯個人資料與 @ID 表單：手機寬度下排得下，欄位檢查即時顯示（不連網路）
 */

const _profile = Profile(
  uid: '11111111-2222-3333-4444-555555555555',
  name: '一個名字非常非常長的使用者用來測試會不會超出畫面',
  username: 'andy.chen',
  email: 'andy.chen.with.a.long.address@example.com',
  photoUrl: '',
  vault: null,
  defaultGroupId: null,
  phoneNumber: '0912-345-678',
);

Future<void> _pump(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(360, 780);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final auth = AuthController(cache: const OfflineCache(), onSignedIn: (_) {}, onSignedOut: (_) {});
  await tester.pumpWidget(ChangeNotifierProvider.value(
    value: auth,
    child: MaterialApp(theme: buildTheme(Brightness.light), home: child),
  ));
}

void main() {
  testWidgets('帳戶區塊：名稱、@ID、電話、活動紀錄、同步 Google 資料', (tester) async {
    await _pump(tester, const Scaffold(body: SingleChildScrollView(child: AccountSection(profile: _profile))));
    expect(find.text('@andy.chen'), findsOneWidget);
    expect(find.text('0912-345-678'), findsOneWidget);
    expect(find.text('活動紀錄'), findsOneWidget);
    expect(find.text('同步 Google 資料'), findsOneWidget);
    expect(find.text('編輯'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('沒有 @ID 時顯示「設定」', (tester) async {
    const profile = Profile(uid: 'u1', name: 'Andy', username: '', email: '', photoUrl: '', vault: null, defaultGroupId: null);
    await _pump(tester, const Scaffold(body: SingleChildScrollView(child: AccountSection(profile: profile))));
    expect(find.text('設定'), findsOneWidget);
    expect(find.text('未設定'), findsOneWidget);
  });

  testWidgets('編輯個人資料：名稱必填；圖片只能上傳，沒有網址欄位', (tester) async {
    await _pump(tester, const ProfileEditForm(profile: _profile));
    expect(find.text(_profile.email), findsOneWidget);
    await tester.enterText(find.byType(TextField).at(0), '  ');
    await tester.pump();
    expect(find.text('請輸入名稱'), findsOneWidget);
    // 只剩名稱與電話兩個輸入欄
    expect(find.byType(TextField), findsNWidgets(2));
    await tester.scrollUntilVisible(find.text('上傳圖片'), 200, scrollable: find.byType(Scrollable).first);
    expect(find.text('上傳照片'), findsOneWidget);
    // 沒有自己上傳的大頭照、沒有背景圖：不用「使用 Google 頭像」「移除背景」
    expect(find.text('使用 Google 頭像'), findsNothing);
    expect(find.text('移除背景'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('@ID：輸入時轉小寫、去掉 @，格式錯誤即時提示', (tester) async {
    await _pump(tester, const UsernameForm(current: 'andy.chen'));
    expect(find.text('這是你目前的 @ID'), findsOneWidget);
    expect(find.text('清除 @ID'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '@AB');
    await tester.pump();
    expect(find.text('ab'), findsOneWidget);
    expect(find.text('@ID 只能使用 3～32 個英文小寫字母、數字、底線（_）或句點（.）'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'admin');
    await tester.pump();
    expect(find.text('這個 @ID 是保留字，不能使用'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '');
    await tester.pump();
    expect(find.text('儲存後會清除 @ID'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
