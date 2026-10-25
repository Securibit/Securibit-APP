import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:securibit/core/result.dart';
import 'package:securibit/core/theme/app_theme.dart';
import 'package:securibit/features/admin/audit_text.dart';
import 'package:securibit/features/admin/notifications/broadcast_models.dart';
import 'package:securibit/features/update/forced_update.dart';
import 'package:securibit/features/update/min_version.dart';
import 'package:securibit/features/update/release.dart';
import 'package:securibit/features/update/update_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

// 最低版本（強制更新）的判斷與畫面、後台發送通知的條件與通知設定

MinVersionController _controller(String current, List<Result<MinVersion?>> answers, {DateTime Function()? clock}) {
  var i = 0;
  return MinVersionController(
    readVersion: () async => current,
    fetch: () async => answers[i < answers.length - 1 ? i++ : i],
    clock: clock,
  );
}

MinVersion _min(String version, [String message = '']) => MinVersion.fromAppConfig({'min_app_version': {'version': version, 'message': message}})!;

void main() {
  group('最低版本', () {
    test('解析 app_config()', () {
      final min = MinVersion.fromAppConfig({'min_app_version': {'version': '1.5.0', 'message': ' 請更新 '}})!;
      expect(min.version.toString(), '1.5.0');
      expect(min.message, '請更新');
      expect(MinVersion.fromAppConfig({'min_app_version': null}), isNull);
      expect(MinVersion.fromAppConfig({'min_app_version': {'version': '不是版本'}}), isNull);
      expect(MinVersion.fromAppConfig(null), isNull);
      expect(MinVersion.fromAppConfig({'version': '1.2.0'})!.version.toString(), '1.2.0');
    });

    test('低於最低版本才擋；預先發行比正式版舊、build 號不算', () {
      expect(belowMinimum('1.4.0', _min('1.5.0')), isTrue);
      expect(belowMinimum('1.5.0', _min('1.5.0')), isFalse);
      expect(belowMinimum('1.5.1', _min('1.5.0')), isFalse);
      expect(belowMinimum('1.5.0-beta.2', _min('1.5.0')), isTrue);
      expect(belowMinimum('1.5.0+9', _min('1.5.0')), isFalse);
      expect(belowMinimum('1.5.0', _min('1.5.0-beta.1')), isFalse);
      // 讀不到就不擋
      expect(belowMinimum(null, _min('9.0.0')), isFalse);
      expect(belowMinimum('1.0.0', null), isFalse);
    });

    test('離線讀不到時保留上一次的結果；清除後放行', () async {
      final controller = _controller('1.4.0', [
        Ok(_min('1.5.0')),
        const Err('無法連線到伺服器，請檢查網路連線', offline: true),
        const Ok(null),
      ]);
      await controller.check();
      expect(controller.required?.version.toString(), '1.5.0');
      expect(MinVersionController.active.value, isTrue);
      await controller.check();
      expect(controller.required, isNotNull);
      await controller.check();
      expect(controller.required, isNull);
      expect(MinVersionController.active.value, isFalse);
    });

    test('第一次就離線：不擋', () async {
      final controller = _controller('1.4.0', [const Err('離線', offline: true)]);
      await controller.check();
      expect(controller.required, isNull);
    });

    test('各平台怎麼更新', () {
      expect(forcedUpdateRoute(isIOS: true, isAndroid: false, updatesEnabled: false, updatesSupported: false), ForcedUpdateRoute.appStore);
      expect(forcedUpdateRoute(isIOS: false, isAndroid: false, updatesEnabled: true, updatesSupported: true), ForcedUpdateRoute.selfUpdate);
      // GitHub 版 Android
      expect(forcedUpdateRoute(isIOS: false, isAndroid: true, updatesEnabled: true, updatesSupported: true), ForcedUpdateRoute.selfUpdate);
      // Google Play 版：不能自己更新
      expect(forcedUpdateRoute(isIOS: false, isAndroid: true, updatesEnabled: false, updatesSupported: false), ForcedUpdateRoute.playStore);
      // 沒有設定 UPDATE_REPO 的桌面版
      expect(forcedUpdateRoute(isIOS: false, isAndroid: false, updatesEnabled: false, updatesSupported: true), ForcedUpdateRoute.browser);
    });

    testWidgets('擋住時整頁蓋上，下面的畫面看不到', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final min = _controller('1.4.0', [Ok(_min('1.5.0', '這個版本有安全問題'))]);
      final updates = UpdateController(
        repo: '',
        target: const UpdateTarget(UpdatePlatform.macos),
        readVersion: () async => '1.4.0',
        client: MockClient((_) async => http.Response('', 404)),
      );
      await updates.load();
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: min),
          ChangeNotifierProvider.value(value: updates),
        ],
        child: MaterialApp(
          theme: buildTheme(Brightness.light),
          builder: (context, child) => ForcedUpdateGate(child: child!),
          home: const Scaffold(body: Text('主畫面')),
        ),
      ));
      expect(find.text('主畫面'), findsOneWidget);
      await tester.runAsync(min.check);
      await tester.pump();
      expect(find.text('強制更新'), findsOneWidget);
      expect(find.text('這個版本有安全問題'), findsOneWidget);
      expect(find.text('目前是 1.4.0，最低需要 1.5.0'), findsOneWidget);
      expect(find.text('主畫面'), findsNothing);
      // 沒有設定檢查更新：只能到下載頁
      expect(find.text('請到 Securibit 的下載頁下載新版'), findsOneWidget);
    });
  });

  group('後台發送通知', () {
    test('條件只送有設定的；所有使用者時不送指定的人、身分組與裝置', () {
      const filter = BroadcastFilter(
        userIds: ['u1'],
        siteRoleIds: ['r1'],
        platforms: ['android', 'web'],
        sessionIds: ['s1'],
        versionMin: ' 1.4.0 ',
        versionMax: '',
        lastSeenDays: 30,
      );
      expect(filter.toJson(), {
        'user_ids': ['u1'],
        'site_role_ids': ['r1'],
        'platforms': ['android', 'web'],
        'session_ids': ['s1'],
        'version_min': '1.4.0',
        'last_seen_days': 30,
      });
      const all = BroadcastFilter(allUsers: true, userIds: ['u1'], siteRoleIds: ['r1'], sessionIds: ['s1'], platforms: ['ios']);
      expect(all.toJson(), {
        'all_users': true,
        'platforms': ['ios'],
      });
      expect(const BroadcastFilter().hasTarget, isFalse);
      // 沒有指定使用者時，裝置也不算
      expect(const BroadcastFilter(sessionIds: ['s1']).hasTarget, isFalse);
    });

    test('發送紀錄的條件說明', () {
      final filter = BroadcastFilter.fromJson({
        'user_ids': ['a', 'b'],
        'site_role_ids': ['r1', 'gone'],
        'platforms': ['web', 'macos'],
        'version_min': '1.4.0',
        'last_seen_days': 7,
      });
      expect(filter.describe({'r1': '測試員'}), '2 位指定的使用者 · 身分組 測試員、已刪除的身分組 · 只用網站、macOS · 版本 1.4.0 ～ 不限 · 最近 7 天用過');
    });

    test('版本格式同網站', () {
      expect(isValidVersion('1.5.0'), isTrue);
      expect(isValidVersion('1.5.0-beta.1'), isTrue);
      expect(isValidVersion('1.5.0+3'), isTrue);
      expect(isValidVersion('1.5'), isFalse);
      expect(isValidVersion('v1.5.0'), isFalse);
      expect(isValidVersion('01.5.0'), isFalse);
    });

    test('預覽與設定的解析', () {
      final preview = BroadcastPreview.fromJson({'users': 12000, 'devices': 80, 'push_devices': 50, 'limit': 10000});
      expect(preview.tooMany, isTrue);
      expect(BroadcastPreview.fromJson({'users': 3, 'devices': 2, 'push_devices': 1}).limit, broadcastUserLimit);
      final settings = SiteSettings.fromJson({
        'notify_admin_changes': {'role': false},
        'min_app_version': {'version': '1.5.0', 'message': '請更新'},
      });
      expect(settings.notifyAdminChanges.role, isFalse);
      expect(settings.notifyAdminChanges.username, isTrue);
      expect(settings.notifyAdminChanges.copyWith('codes', false).toJson(), {'role': false, 'username': true, 'codes': false});
      expect(settings.minAppVersion?.version, '1.5.0');
      expect(SiteSettings.fromJson({'min_app_version': null}).minAppVersion, isNull);
    });

    test('操作紀錄的文字', () {
      expect(auditActionText('notification.broadcast'), '發送通知');
      expect(auditActionText('site.settings.update'), '修改網站設定');
      expect(auditChangeText('notification.broadcast', {'user_count': 120}), '120 位使用者');
      expect(
        auditChangeText('site.settings.update', {
          'name': 'min_app_version',
          'value': {'version': '1.5.0'},
          'old_value': null,
        }),
        '未設定 → 1.5.0',
      );
      expect(
        auditChangeText('site.settings.update', {
          'name': 'notify_admin_changes',
          'value': {'role': false, 'username': true},
        }),
        '（無） → 變更網站身分組關、修改 @ID開',
      );
    });
  });
}
