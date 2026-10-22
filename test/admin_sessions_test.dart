import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:securibit/core/theme/app_theme.dart';
import 'package:securibit/features/admin/admin_models.dart';
import 'package:securibit/features/profile/devices_page.dart';
import 'package:securibit/features/profile/session_models.dart';

SessionRecord session({bool current = false}) => SessionRecord.fromJson({
      'id': 's1',
      'created_at': '2026-10-20T01:00:00Z',
      'updated_at': '2026-10-21T01:00:00Z',
      'refreshed_at': null,
      'last_active_at': '2026-10-22T01:00:00Z',
      'user_agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15',
      'ip': null,
      'aal': 'aal1',
      'current': current,
      'device_name': null,
      'platform': null,
      'app_version': null,
    });

Widget host(Widget child) => MaterialApp(theme: buildTheme(Brightness.light), home: Scaffold(body: child));

// 後台的「最後活動」與已登入的裝置（admin_users、admin_user、admin_user_sessions）
void main() {
  group('last_active_at', () {
    test('admin_user 有最後活動', () {
      final detail = AdminUserDetail.fromJson({'id': 'u1', 'last_active_at': '2026-10-22T01:00:00Z', 'groups': []});
      expect(detail.user.lastActiveAt, '2026-10-22T01:00:00Z');
    });

    test('沒有登入中的裝置（null）或舊的資料庫沒有欄位都是 null', () {
      expect(AdminUser.fromJson({'id': 'u1', 'last_active_at': null}).lastActiveAt, isNull);
      expect(AdminUser.fromJson({'id': 'u1'}).lastActiveAt, isNull);
    });

    test('admin_users 每一列都有', () {
      final page = AdminUserPage.fromJson({
        'total': 2,
        'users': [
          {'id': 'a', 'last_active_at': '2026-10-22T01:00:00Z'},
          {'id': 'b'},
        ],
      });
      expect(page.users.map((u) => u.lastActiveAt), ['2026-10-22T01:00:00Z', null]);
    });
  });

  group('SessionRow', () {
    testWidgets('個人頁面：這台標「這台裝置」，其他的有「登出」', (tester) async {
      await tester.pumpWidget(host(Column(children: [
        SessionRow(session: session(current: true), onRevoke: (_) {}),
        SessionRow(session: session(), onRevoke: (_) {}),
      ])));
      expect(find.text('這台裝置'), findsOneWidget);
      expect(find.text('登出'), findsOneWidget);
    });

    testWidgets('後台只能查看：沒有「這台裝置」也沒有「登出」，其他內容一樣', (tester) async {
      await tester.pumpWidget(host(Column(children: [
        SessionRow(session: session(current: true), readOnly: true),
        SessionRow(session: session(), readOnly: true),
      ])));
      expect(find.text('這台裝置'), findsNothing);
      expect(find.text('登出'), findsNothing);
      expect(find.text('Mac'), findsNWidgets(2));
      expect(find.textContaining('最後活動'), findsNWidgets(2));
      expect(find.textContaining('首次登入'), findsNWidgets(2));
    });
  });
}
