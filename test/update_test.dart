import 'dart:convert';
import 'dart:ffi' show Abi;
import 'dart:io' show SocketException;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:securibit/core/theme/app_theme.dart';
import 'package:securibit/features/update/app_version.dart';
import 'package:securibit/features/update/release.dart';
import 'package:securibit/features/update/update_controller.dart';
import 'package:securibit/features/update/update_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

// 檢查更新：版本比較、Release 解析、各平台的安裝檔、略過版本與失敗時的狀態（假的 HTTP，不連網）
AppVersion _v(String text) => AppVersion.tryParse(text)!;

const _repo = 'Securibit/Securibit-APP';
const _mac = UpdateTarget(UpdatePlatform.macos);

Map<String, Object?> _releaseJson(String tag, {List<String> assets = const [], String body = '', bool draft = false, bool prerelease = false}) => {
      'tag_name': tag,
      'html_url': 'https://github.com/$_repo/releases/tag/$tag',
      'body': body,
      'draft': draft,
      'prerelease': prerelease,
      'assets': [
        for (final name in assets) {'name': name, 'browser_download_url': 'https://dl.example/$name'},
      ],
    };

AppRelease _release(String tag, [List<String> assets = const []]) => AppRelease.fromJson(_releaseJson(tag, assets: assets))!;

void main() {
  group('版本比較', () {
    test('解析 v 開頭、少寫的部分與 build 號', () {
      expect(_v('v0.3.0').toString(), '0.3.0');
      expect(_v('0.3.0+3').toString(), '0.3.0');
      expect(_v('V1.2').toString(), '1.2.0');
      expect(_v('2').toString(), '2.0.0');
      expect(_v('1.0.0-beta.1').toString(), '1.0.0-beta.1');
      for (final bad in ['', 'latest', 'v', '1.x', '1.0.0.0', 'release-1.0']) {
        expect(AppVersion.tryParse(bad), isNull, reason: bad);
      }
    });

    test('數字逐段比，不是比字串', () {
      expect(_v('0.10.0') > _v('0.9.9'), isTrue);
      expect(_v('1.0.0') > _v('0.99.99'), isTrue);
      expect(_v('0.3.1') > _v('0.3.0'), isTrue);
      expect(_v('0.3.0') > _v('0.3.0'), isFalse);
      expect(_v('0.2.9') > _v('0.3.0'), isFalse);
    });

    test('build 號不算，v 有沒有寫都一樣', () {
      expect(_v('0.3.0+9'), _v('v0.3.0'));
      expect(_v('0.3.0+9') > _v('0.3.0+3'), isFalse);
    });

    test('預先發行比正式版舊，各段依 semver 的規則比', () {
      final ordered = ['1.0.0-alpha', '1.0.0-alpha.1', '1.0.0-alpha.beta', '1.0.0-beta', '1.0.0-beta.2', '1.0.0-beta.11', '1.0.0-rc.1', '1.0.0'];
      for (var i = 0; i + 1 < ordered.length; i++) {
        expect(_v(ordered[i + 1]) > _v(ordered[i]), isTrue, reason: '${ordered[i + 1]} > ${ordered[i]}');
        expect(_v(ordered[i]) > _v(ordered[i + 1]), isFalse);
      }
    });
  });

  group('Release 解析', () {
    test('讀出標籤、說明、頁面與附件', () {
      final release = AppRelease.fromJson(_releaseJson('v0.4.0', body: '更新內容', assets: ['a.dmg']))!;
      expect(release.version, _v('0.4.0'));
      expect(release.fileVersion, '0.4.0');
      expect(release.notes, '更新內容');
      expect(release.pageUrl, 'https://github.com/$_repo/releases/tag/v0.4.0');
      expect(release.assets.single.url, 'https://dl.example/a.dmg');
    });

    test('草稿、預先發行、看不懂的標籤都不算', () {
      expect(AppRelease.fromJson(_releaseJson('v0.4.0', draft: true)), isNull);
      expect(AppRelease.fromJson(_releaseJson('v0.4.0', prerelease: true)), isNull);
      expect(AppRelease.fromJson(_releaseJson('nightly')), isNull);
      expect(AppRelease.fromJson({'message': 'Not Found'}), isNull);
      expect(AppRelease.fromJson(null), isNull);
    });

    test('Markdown 拆成標題、段落、清單與表格，「下載」段落拿掉', () {
      const markdown = '說明第一段\r\n\r\n## 新功能\r\n\r\n**群組**\r\n- **檢查更新**：看 [GitHub](https://github.com)\r\n  - 子項目\r\n1. 第一步\r\n\r\n'
          '## 下載\r\n\r\n| 平台 | 檔案 |\r\n|---|---|\r\n| macOS | `a.dmg` |\r\n\r\n## 注意\r\n\r\n| 甲 | 乙 |\r\n|:--|--:|\r\n| 1 | 2 |\r\n<!-- 註解 -->結尾 ##';
      final blocks = releaseNoteBlocks(markdown);
      expect([for (final b in blocks) b.type], [
        NoteBlockType.paragraph,
        NoteBlockType.heading,
        NoteBlockType.paragraph,
        NoteBlockType.bullet,
        NoteBlockType.bullet,
        NoteBlockType.bullet,
        NoteBlockType.heading,
        NoteBlockType.table,
        NoteBlockType.paragraph,
      ]);
      expect(blocks[1].text, '新功能');
      expect(blocks[3].text, '**檢查更新**：看 [GitHub](https://github.com)');
      expect((blocks[4].depth, blocks[4].marker), (1, '•'));
      expect(blocks[5].marker, '1.');
      expect(blocks[6].text, '注意');
      expect(blocks[7].rows, [['甲', '乙'], ['1', '2']]);
      expect(blocks.any((b) => b.text.contains('macOS') || b.rows.any((r) => r.contains('macOS'))), isFalse);
      expect(releaseNoteBlocks('   '), isEmpty);
    });
  });

  group('各平台的安裝檔', () {
    const all = [
      'Securibit-0.4.0-macos.zip',
      'Securibit-0.4.0-macos.dmg',
      'Securibit-0.4.0-linux-x64.tar.gz',
      'Securibit-0.4.0-linux-arm64.tar.gz',
      'securibit_0.4.0_amd64.deb',
      'securibit_0.4.0_arm64.deb',
      'securibit-0.4.0-arm64-v8a.apk',
      'securibit-0.4.0-armeabi-v7a.apk',
      'securibit-0.4.0-x86_64.apk',
      'securibit-0.4.0.aab',
      'Securibit-0.4.0-windows-x64-setup.exe',
      'Securibit-0.4.0-windows-x64.zip',
    ];
    final release = _release('v0.4.0', all);
    String file(UpdateTarget target) => release.downloadUrl(target).replaceFirst('https://dl.example/', '');

    test('macOS 先找 .dmg，沒有才用 .zip', () {
      expect(file(_mac), 'Securibit-0.4.0-macos.dmg');
      expect(_release('0.4.0', ['Securibit-0.4.0-macos.zip']).downloadUrl(_mac), 'https://dl.example/Securibit-0.4.0-macos.zip');
    });

    test('Linux：.deb 安裝的找 .deb，其他找 .tar.gz，依處理器架構', () {
      expect(file(const UpdateTarget(UpdatePlatform.linux, arch: 'x64', deb: true)), 'securibit_0.4.0_amd64.deb');
      expect(file(const UpdateTarget(UpdatePlatform.linux, arch: 'arm64', deb: true)), 'securibit_0.4.0_arm64.deb');
      expect(file(const UpdateTarget(UpdatePlatform.linux, arch: 'x64')), 'Securibit-0.4.0-linux-x64.tar.gz');
      expect(file(const UpdateTarget(UpdatePlatform.linux, arch: 'arm64')), 'Securibit-0.4.0-linux-arm64.tar.gz');
      // 這一版沒有 .deb 時，.deb 安裝的退回 .tar.gz
      final tarOnly = _release('v0.4.0', ['Securibit-0.4.0-linux-x64.tar.gz']);
      expect(tarOnly.downloadUrl(const UpdateTarget(UpdatePlatform.linux, arch: 'x64', deb: true)), 'https://dl.example/Securibit-0.4.0-linux-x64.tar.gz');
    });

    test('Android 依 ABI 找 APK', () {
      expect(file(const UpdateTarget(UpdatePlatform.android, arch: 'arm64-v8a')), 'securibit-0.4.0-arm64-v8a.apk');
      expect(file(const UpdateTarget(UpdatePlatform.android, arch: 'armeabi-v7a')), 'securibit-0.4.0-armeabi-v7a.apk');
      expect(file(const UpdateTarget(UpdatePlatform.android, arch: 'x86_64')), 'securibit-0.4.0-x86_64.apk');
      // 沒有分處理器時用通用的 APK（舊版的檔名在版本前面帶 v）
      const arm64 = UpdateTarget(UpdatePlatform.android, arch: 'arm64-v8a');
      expect(_release('v0.4.0', ['securibit-0.4.0.apk']).downloadUrl(arm64), 'https://dl.example/securibit-0.4.0.apk');
      expect(_release('v0.2.1-beta.2', ['securibit-v0.2.1-beta.2.apk']).downloadUrl(arm64), 'https://dl.example/securibit-v0.2.1-beta.2.apk');
      expect(_release('v0.4.0', ['securibit-0.4.0-x86_64.apk']).downloadUrl(arm64), 'https://github.com/$_repo/releases/tag/v0.4.0');
    });

    test('Windows：安裝檔裝的先找 setup.exe，免安裝版先找 .zip；缺一種時用另一種', () {
      expect(file(const UpdateTarget(UpdatePlatform.windows, arch: 'x64', setup: true)), 'Securibit-0.4.0-windows-x64-setup.exe');
      expect(file(const UpdateTarget(UpdatePlatform.windows, arch: 'x64')), 'Securibit-0.4.0-windows-x64.zip');
      final setupOnly = _release('v0.4.0', ['Securibit-0.4.0-windows-x64-setup.exe']);
      expect(setupOnly.downloadUrl(const UpdateTarget(UpdatePlatform.windows, arch: 'x64')), 'https://dl.example/Securibit-0.4.0-windows-x64-setup.exe');
      final zipOnly = _release('v0.4.0', ['Securibit-0.4.0-windows-x64.zip']);
      expect(zipOnly.downloadUrl(const UpdateTarget(UpdatePlatform.windows, arch: 'x64', setup: true)), 'https://dl.example/Securibit-0.4.0-windows-x64.zip');
      // 認不得架構（目前只有 x64）就開 Release 頁面
      expect(release.downloadUrl(const UpdateTarget(UpdatePlatform.windows, setup: true)), 'https://github.com/$_repo/releases/tag/v0.4.0');
    });

    test('Abi 對到檔名用的架構名稱', () {
      expect(UpdateTarget.windowsArch(Abi.windowsX64), 'x64');
      expect(UpdateTarget.windowsArch(Abi.windowsArm64), isNull);
      expect(UpdateTarget.linuxArch(Abi.linuxX64), 'x64');
      expect(UpdateTarget.linuxArch(Abi.linuxArm64), 'arm64');
      expect(UpdateTarget.linuxArch(Abi.linuxRiscv64), isNull);
      expect(UpdateTarget.androidAbi(Abi.androidArm64), 'arm64-v8a');
      expect(UpdateTarget.androidAbi(Abi.androidArm), 'armeabi-v7a');
      expect(UpdateTarget.androidAbi(Abi.androidX64), 'x86_64');
      expect(UpdateTarget.androidAbi(Abi.androidIA32), isNull);
    });

    test('找不到對應的檔案（或認不得架構）就開 Release 頁面', () {
      final page = 'https://github.com/$_repo/releases/tag/v0.4.0';
      expect(_release('v0.4.0', ['notes.txt']).downloadUrl(_mac), page);
      expect(release.downloadUrl(const UpdateTarget(UpdatePlatform.linux)), page);
      expect(_release('v0.4.0', ['securibit-0.4.0-arm64-v8a.apk']).downloadUrl(const UpdateTarget(UpdatePlatform.android)), page);
      // 檔名的版本要和標籤相同
      expect(_release('v0.4.1', all).downloadUrl(_mac), 'https://github.com/$_repo/releases/tag/v0.4.1');
    });

    test('檔名不分大小寫', () {
      expect(_release('v0.4.0', ['securibit-0.4.0-MACOS.DMG']).downloadUrl(_mac), 'https://dl.example/securibit-0.4.0-MACOS.DMG');
    });
  });

  group('UpdateController', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    final requests = <http.Request>[];

    UpdateController controller({
      String repo = _repo,
      UpdateTarget? target = _mac,
      String current = '0.3.0',
      required Future<http.Response> Function(http.Request request) respond,
    }) {
      requests.clear();
      return UpdateController(
        repo: repo,
        target: target,
        readVersion: () async => current,
        client: MockClient((request) {
          requests.add(request);
          return respond(request);
        }),
      );
    }

    http.Response json(Object body, [int status = 200]) =>
        http.Response.bytes(utf8.encode(jsonEncode(body)), status, headers: {'content-type': 'application/json; charset=utf-8'});

    test('打 releases/latest，有新版本時回傳它', () async {
      final updates = controller(respond: (_) async => json(_releaseJson('v0.4.0', body: '新功能')));
      await updates.load();
      expect(updates.enabled, isTrue);
      expect(updates.currentVersion, '0.3.0');
      final release = await updates.check();
      expect(release?.version, _v('0.4.0'));
      expect(updates.status, UpdateStatus.available);
      expect(updates.latest?.notes, '新功能');
      expect(requests.single.url.toString(), 'https://api.github.com/repos/$_repo/releases/latest');
      expect(requests.single.headers['Accept'], 'application/vnd.github+json');
      expect(requests.single.headers.containsKey('Authorization'), isFalse);
    });

    test('一樣或更舊的版本、沒有任何 Release（404）都算已是最新版本', () async {
      for (final response in [
        json(_releaseJson('v0.3.0')),
        json(_releaseJson('0.2.9')),
        json({'message': 'Not Found'}, 404),
      ]) {
        final updates = controller(respond: (_) async => response);
        await updates.load();
        expect(await updates.check(), isNull);
        expect(updates.status, UpdateStatus.upToDate);
      }
    });

    test('離線、API 錯誤、不是 JSON 時不丟例外，狀態是 failed', () async {
      for (final respond in <Future<http.Response> Function(http.Request)>[
        (_) async => throw const SocketException('offline'),
        (_) async => json({'message': 'API rate limit exceeded'}, 403),
        (_) async => http.Response('<html>', 200),
      ]) {
        final updates = controller(respond: respond);
        await updates.load();
        expect(await updates.check(), isNull);
        expect(await updates.checkAutomatically(), isNull);
        expect(updates.status, UpdateStatus.failed);
        expect(updates.lastCheckedAt, isNotNull);
      }
    });

    test('沒有設定 repo、格式不對、iOS（沒有 target）、讀不到版本時不檢查', () async {
      for (final updates in [
        controller(repo: '', respond: (_) async => json(_releaseJson('v9.0.0'))),
        controller(repo: 'not a repo', respond: (_) async => json(_releaseJson('v9.0.0'))),
        controller(target: null, respond: (_) async => json(_releaseJson('v9.0.0'))),
        controller(current: '', respond: (_) async => json(_releaseJson('v9.0.0'))),
      ]) {
        await updates.load();
        expect(updates.enabled, isFalse);
        expect(await updates.check(), isNull);
        expect(requests, isEmpty);
      }
      expect(controller(target: null, respond: (_) async => json({})).supported, isFalse);
    });

    test('有新版本時自動檢查每次都提示（不能略過），舊版留下的略過紀錄會清掉', () async {
      SharedPreferences.setMockInitialValues({'securibit:updateSkipped': '0.4.0'});
      final updates = controller(respond: (_) async => json(_releaseJson('v0.4.0')));
      await updates.load();
      expect((await updates.checkAutomatically())?.version, _v('0.4.0'));
      expect((await updates.checkAutomatically())?.version, _v('0.4.0'));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('securibit:updateSkipped'), isFalse);
    });

    test('關掉啟動時檢查更新就不自動檢查，設定記在裝置上', () async {
      final updates = controller(respond: (_) async => json(_releaseJson('v0.4.0')));
      await updates.load();
      updates.setCheckOnLaunch(false);
      expect(await updates.checkAutomatically(), isNull);
      expect(requests, isEmpty);
      // 手動檢查不受影響
      expect(await updates.check(), isNotNull);

      final reopened = controller(respond: (_) async => json({}));
      await reopened.load();
      expect(reopened.checkOnLaunch, isFalse);
    });

    test('同時檢查只送一個請求；下載網址依平台', () async {
      final updates = controller(respond: (_) async => json(_releaseJson('v0.4.0', assets: ['Securibit-0.4.0-macos.dmg'])));
      await updates.load();
      final results = await Future.wait([updates.check(), updates.check()]);
      expect(requests, hasLength(1));
      expect(updates.downloadUrl(results.first!), 'https://dl.example/Securibit-0.4.0-macos.dmg');
    });

    test('距離上次檢查超過一天才算該再查', () async {
      var now = DateTime(2026, 1, 1, 9);
      final updates = UpdateController(
        repo: _repo,
        target: _mac,
        readVersion: () async => '0.3.0',
        clock: () => now,
        client: MockClient((_) async => json(_releaseJson('v0.3.0'))),
      );
      await updates.load();
      expect(updates.isDue(const Duration(days: 1)), isTrue);
      await updates.check();
      now = now.add(const Duration(hours: 23));
      expect(updates.isDue(const Duration(days: 1)), isFalse);
      now = now.add(const Duration(hours: 1));
      expect(updates.isDue(const Duration(days: 1)), isTrue);
    });
  });

  testWidgets('不能自動安裝時的提示：版本與排版後的更新內容，只有「稍後」與「用瀏覽器下載」', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final updates = UpdateController(
      repo: _repo,
      target: _mac,
      readVersion: () async => '0.3.0',
      client: MockClient((_) async => http.Response('{}', 404)),
    );
    await tester.runAsync(updates.load);
    final release = AppRelease.fromJson(_releaseJson('v0.4.0', body: '## 新功能\n- **檢查更新**'))!;
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.light),
      home: Builder(
        builder: (context) => TextButton(onPressed: () => showUpdatePrompt(context, updates, release), child: const Text('open')),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('有新版本，強烈建議更新'), findsOneWidget);
    expect(find.text('Securibit 0.4.0 已推出，目前是 0.3.0'), findsOneWidget);
    expect(find.text('新功能'), findsOneWidget);
    expect(find.text('檢查更新', findRichText: true), findsOneWidget);
    expect(find.text('•'), findsOneWidget);
    for (final label in ['用瀏覽器下載', '稍後']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('略過這個版本'), findsNothing);
    await tester.tap(find.text('稍後'));
    await tester.pumpAndSettle();
    expect(find.text('有新版本，強烈建議更新'), findsNothing);
  });

  testWidgets('開在鎖定畫面上的提示：解鎖時跟著消失回傳 false，之後還能再提示', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final updates = UpdateController(
      repo: _repo,
      target: _mac,
      readVersion: () async => '0.3.0',
      client: MockClient((_) async => http.Response('{}', 404)),
    );
    await tester.runAsync(updates.load);
    final release = AppRelease.fromJson(_releaseJson('v0.4.0'))!;
    final locked = ValueNotifier(true);
    final lockNavigator = GlobalKey<NavigatorState>();
    final appNavigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.light),
      navigatorKey: appNavigator,
      home: const SizedBox.shrink(),
      builder: (context, child) => ValueListenableBuilder<bool>(
        valueListenable: locked,
        builder: (context, value, _) => Stack(children: [
          child!,
          if (value)
            HeroControllerScope.none(
              child: Navigator(key: lockNavigator, onGenerateRoute: (_) => PageRouteBuilder<void>(pageBuilder: (_, _, _) => const SizedBox.shrink())),
            ),
        ]),
      ),
    ));

    bool? answered;
    showUpdatePrompt(lockNavigator.currentContext!, updates, release).then((value) => answered = value);
    await tester.pumpAndSettle();
    expect(find.text('有新版本，強烈建議更新'), findsOneWidget);

    locked.value = false;
    await tester.pumpAndSettle();
    expect(answered, isFalse);
    expect(find.text('有新版本，強烈建議更新'), findsNothing);

    showUpdatePrompt(appNavigator.currentContext!, updates, release).then((value) => answered = value);
    await tester.pumpAndSettle();
    expect(find.text('有新版本，強烈建議更新'), findsOneWidget);
    await tester.tap(find.text('稍後'));
    await tester.pumpAndSettle();
    expect(answered, isTrue);
  });
}
