import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:securibit/core/theme/app_theme.dart';
import 'package:securibit/features/profile/devices_page.dart';
import 'package:securibit/features/profile/session_models.dart';

/*
 * 已登入的裝置：list_my_sessions 的解析、user-agent 的判斷（同網站 parseUserAgent）、
 * 裝置名稱的組法，以及手機寬度下一列排得下（不連網路）
 */

Map<String, dynamic> _row({
  bool current = false,
  String? userAgent,
  String? deviceName,
  String? platform,
  String? appVersion,
  String? ip,
}) =>
    {
      'id': 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee',
      'created_at': '2026-10-01T08:00:00+00:00',
      'updated_at': '2026-10-20T08:00:00+00:00',
      'refreshed_at': '2026-10-21T08:00:00+00:00',
      'last_active_at': '2026-10-21T08:00:00+00:00',
      'user_agent': userAgent,
      'ip': ip,
      'aal': 'aal1',
      'current': current,
      'device_name': deviceName,
      'platform': platform,
      'app_version': appVersion,
    };

String _jwt(Map<String, dynamic> payload) {
  String part(Object value) => base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return '${part({'alg': 'HS256'})}.${part(payload)}.signature';
}

void main() {
  test('list_my_sessions 的一筆', () {
    final session = SessionRecord.fromJson(_row(current: true, platform: 'ios', appVersion: '1.2.0', ip: '1.2.3.4'));
    expect(session.id, 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee');
    expect(session.current, isTrue);
    expect(session.platform, 'ios');
    expect(session.ip, '1.2.3.4');
    expect(session.lastActiveAt, '2026-10-21T08:00:00+00:00');
    expect(session.createdAt, '2026-10-01T08:00:00+00:00');
  });

  test('user-agent：系統、瀏覽器與裝置種類', () {
    const mac = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) '
        'Chrome/130.0.0.0 Safari/537.36';
    expect(parseUserAgent(mac), (os: 'macOS', browser: 'Chrome', device: 'Mac'));
    const iphone = 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 '
        '(KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1';
    expect(parseUserAgent(iphone), (os: 'iOS', browser: 'Safari', device: 'iPhone'));
    const edge = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) '
        'Chrome/130.0.0.0 Safari/537.36 Edg/130.0.0.0';
    expect(parseUserAgent(edge), (os: 'Windows', browser: 'Edge', device: 'Windows 電腦'));
    expect(parseUserAgent('Dart/3.9 (dart:io)').browser, 'Securibit App');
    expect(parseUserAgent('SecuribitApp (Linux; Android)'), (os: 'Android', browser: 'Securibit App', device: 'Android 裝置'));
    expect(parseUserAgent('SecuribitApp/1.3.2 (Macintosh; Mac OS X)'), (os: 'macOS', browser: 'Securibit App 1.3.2', device: 'Mac'));
    expect(parseUserAgent(''), (os: '未知系統', browser: '未知瀏覽器', device: '未知裝置'));
  });

  test('裝置名稱：App 回報的優先，否則從 user-agent 解析', () {
    final app = SessionRecord.fromJson(_row(
      userAgent: 'Dart/3.9 (dart:io)',
      deviceName: 'Google Pixel 8',
      platform: 'android',
      appVersion: '1.2.0',
    ));
    expect(sessionDisplay(app), (name: 'Google Pixel 8', platform: 'Android', client: 'Securibit App 1.2.0'));

    final noName = SessionRecord.fromJson(_row(platform: 'macos'));
    expect(sessionDisplay(noName), (name: 'macOS', platform: 'macOS', client: 'Securibit App'));

    final web = SessionRecord.fromJson(_row(userAgent: 'Mozilla/5.0 (X11; Linux x86_64; rv:131.0) Gecko/20100101 Firefox/131.0'));
    expect(sessionDisplay(web), (name: 'Linux 電腦', platform: 'Linux', client: 'Firefox'));

    // 還沒回報過的 App（舊版）
    final oldApp = SessionRecord.fromJson(_row(userAgent: 'Dart/3.9 (dart:io)'));
    expect(sessionDisplay(oldApp).client, 'Securibit App');
  });

  test('access token 的 session_id', () {
    expect(sessionIdOf(_jwt({'sub': 'u1', 'session_id': 'abc-123'})), 'abc-123');
    expect(sessionIdOf(_jwt({'sub': 'u1'})), isNull);
    expect(sessionIdOf('not-a-jwt'), isNull);
    expect(sessionIdOf('a.%%%.c'), isNull);
  });

  test('主機名稱', () {
    expect(cleanHostname('Tershis-MacBook-Pro.local'), 'Tershis-MacBook-Pro');
    expect(cleanHostname('localhost'), isNull);
    expect(cleanHostname('  '), isNull);
    expect(cleanHostname('a' * 150)!.length, 100);
  });

  testWidgets('手機寬度：名稱很長、有 IP、這台與其他裝置都排得下', (tester) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final current = SessionRecord.fromJson(_row(
      current: true,
      deviceName: '一台名字非常非常長的電腦用來測試會不會超出畫面的 MacBook Pro',
      platform: 'macos',
      appVersion: '1.2.0',
      ip: '2001:db8:85a3::8a2e:370:7334',
    ));
    final other = SessionRecord.fromJson(_row(
      userAgent: 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 Version/18.0 Safari/604.1',
      ip: '203.0.113.7',
    ));
    String? revoked;
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.light),
      home: Scaffold(
        body: Column(children: [
          SessionRow(session: current, onRevoke: (_) {}),
          SessionRow(session: other, onRevoke: (name) => revoked = name),
        ]),
      ),
    ));
    expect(tester.takeException(), isNull);
    expect(find.text('這台裝置'), findsOneWidget);
    // 這台裝置沒有「登出」，其他的有
    expect(find.text('登出'), findsOneWidget);
    expect(find.text('iOS · Safari · 203.0.113.7'), findsOneWidget);
    expect(find.textContaining('最後活動'), findsNWidgets(2));
    expect(find.textContaining('首次登入'), findsNWidgets(2));
    await tester.tap(find.text('登出'));
    expect(revoked, 'iPhone');
  });
}
