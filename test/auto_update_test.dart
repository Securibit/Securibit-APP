import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:securibit/core/secure_store.dart';
import 'package:securibit/core/theme/app_theme.dart';
import 'package:securibit/features/update/checksums.dart';
import 'package:securibit/features/update/helper_scripts.dart';
import 'package:securibit/features/update/install_location.dart';
import 'package:securibit/features/update/release.dart';
import 'package:securibit/features/update/update_controller.dart';
import 'package:securibit/features/update/update_dialog.dart';
import 'package:securibit/features/update/update_installer.dart';
import 'package:shared_preferences/shared_preferences.dart';

// 自動更新：要下載哪個檔案、SHA256SUMS 的解析與比對、下載與驗證的狀態、安裝方式的判斷、替換腳本（假的 HTTP，不連網）

const _mac = UpdateTarget(UpdatePlatform.macos);
const _zip = 'Securibit-1.2.0-macos.zip';
const _feed = 'https://api.github.com/repos/Securibit/Securibit-APP/releases/latest';

Map<String, Object?> _releaseJson(String tag, List<String> assets) => {
      'tag_name': tag,
      'html_url': 'https://github.com/Securibit/Securibit-APP/releases/tag/$tag',
      'body': '## 新功能\n- 自動更新',
      'draft': false,
      'prerelease': false,
      'assets': [
        for (final name in assets) {'name': name, 'browser_download_url': 'https://dl.example/$name'},
      ],
    };

String _hex(List<int> bytes) => sha256.convert(bytes).toString();

/// 假的安裝方式：檔案放在暫存資料夾，記錄被呼叫了什麼
class _FakeInstaller extends UpdateInstaller {
  _FakeInstaller(this.root);

  final Directory root;
  InstallSupport supportResult = const InstallSupport.auto();
  Object? prepareError;
  final prepared = <String>[];
  final armed = <String>[];
  final installed = <String>[];
  InstallResult installResult = InstallResult.started;

  @override
  Future<Directory?> workDir() async => root;

  @override
  Future<InstallSupport> support() async => supportResult;

  @override
  Future<void> prepare(File download, Directory stage, AppRelease release) async {
    final error = prepareError;
    if (error != null) throw error;
    prepared.add(download.path);
    await File('${stage.path}/prepared').writeAsString('ok');
  }

  @override
  Future<bool> isPrepared(Directory stage) => File('${stage.path}/prepared').exists();

  @override
  Future<void> armOnQuit(Directory stage) async => armed.add(stage.path);

  @override
  Future<InstallOutcome> install(Directory stage, File download) async {
    installed.add(download.path);
    return InstallOutcome(installResult);
  }
}

/// 假的伺服器：最新版 JSON、SHA256SUMS.txt 與安裝檔
class _Server {
  _Server({List<String>? assets}) : assets = assets ?? [_zip, 'Securibit-1.2.0-macos.dmg', 'SHA256SUMS.txt'];

  String tag = 'v1.2.0';
  List<String> assets;
  List<int> payload = utf8.encode('新版的 zip 內容');
  // null：照實際內容算
  String? sums;
  int failuresLeft = 0;
  final requests = <String>[];

  MockClient get client => MockClient((request) async {
        final url = request.url.toString();
        requests.add(url);
        if (url == _feed || url.startsWith('http://127.0.0.1')) {
          return http.Response.bytes(utf8.encode(jsonEncode(_releaseJson(tag, assets))), 200);
        }
        if (url.endsWith('SHA256SUMS.txt')) {
          return http.Response(sums ?? '${_hex(payload)}  $_zip\n${'0' * 64}  Securibit-1.2.0-macos.dmg\n', 200);
        }
        if (url.endsWith(_zip)) {
          if (failuresLeft > 0) {
            failuresLeft--;
            return http.Response('busy', 503);
          }
          return http.Response.bytes(payload, 200);
        }
        return http.Response('not found', 404);
      });

  int get downloads => requests.where((u) => u.endsWith(_zip)).length;
}

// 替換腳本用 /bin/sh 執行（macOS、Linux），Windows 沒有
final _noShell = Platform.isWindows ? 'Windows 沒有 /bin/sh' : false;

// 等背景的下載告一段落
Future<void> _settle(UpdateController updates) async {
  for (var i = 0; i < 400; i++) {
    if (updates.status != UpdateStatus.downloading && updates.status != UpdateStatus.checking) return;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  fail('一直在下載：${updates.status}');
}

void main() {
  group('要下載的檔案', () {
    final release = AppRelease.fromJson(_releaseJson('v1.2.0', [
      'Securibit-1.2.0-macos.dmg',
      _zip,
      'securibit_1.2.0_amd64.deb',
      'Securibit-1.2.0-linux-x64.tar.gz',
      'securibit-1.2.0-arm64-v8a.apk',
      'securibit-1.2.0-x86_64.apk',
      'Securibit-1.2.0-windows-x64-setup.exe',
      'Securibit-1.2.0-windows-x64.zip',
      'SHA256SUMS.txt',
    ]))!;

    test('自動安裝：macOS 用 .zip（瀏覽器下載仍先找 .dmg）', () {
      expect(release.installAsset(_mac)?.name, _zip);
      expect(release.downloadUrl(_mac), 'https://dl.example/Securibit-1.2.0-macos.dmg');
      final dmgOnly = AppRelease.fromJson(_releaseJson('v1.2.0', ['Securibit-1.2.0-macos.dmg']))!;
      expect(dmgOnly.installAsset(_mac), isNull);
    });

    test('自動安裝：Linux 的 .deb 只用 .deb、.tar.gz 只用 .tar.gz；Android 依 ABI', () {
      expect(release.installAsset(const UpdateTarget(UpdatePlatform.linux, arch: 'x64', deb: true))?.name, 'securibit_1.2.0_amd64.deb');
      expect(release.installAsset(const UpdateTarget(UpdatePlatform.linux, arch: 'x64'))?.name, 'Securibit-1.2.0-linux-x64.tar.gz');
      expect(release.installAsset(const UpdateTarget(UpdatePlatform.linux, arch: 'arm64', deb: true)), isNull);
      expect(release.installAsset(const UpdateTarget(UpdatePlatform.android, arch: 'arm64-v8a'))?.name, 'securibit-1.2.0-arm64-v8a.apk');
      expect(release.installAsset(const UpdateTarget(UpdatePlatform.android, arch: 'armeabi-v7a')), isNull);
    });

    test('自動安裝：Windows 安裝檔裝的只用 setup.exe；免安裝版不自動安裝（用瀏覽器下載 .zip）', () {
      const setup = UpdateTarget(UpdatePlatform.windows, arch: 'x64', setup: true);
      const portable = UpdateTarget(UpdatePlatform.windows, arch: 'x64');
      expect(release.installAsset(setup)?.name, 'Securibit-1.2.0-windows-x64-setup.exe');
      expect(release.installAsset(portable), isNull);
      expect(release.downloadUrl(portable), 'https://dl.example/Securibit-1.2.0-windows-x64.zip');
      final zipOnly = AppRelease.fromJson(_releaseJson('v1.2.0', ['Securibit-1.2.0-windows-x64.zip']))!;
      expect(zipOnly.installAsset(setup), isNull);
    });

    test('檢查碼清單：SHA256SUMS.txt（不分大小寫）', () {
      expect(release.checksumsAsset?.name, 'SHA256SUMS.txt');
      expect(AppRelease.fromJson(_releaseJson('v1.2.0', ['sha256sums.TXT']))!.checksumsAsset, isNotNull);
      expect(AppRelease.fromJson(_releaseJson('v1.2.0', [_zip]))!.checksumsAsset, isNull);
    });
  });

  group('SHA256SUMS', () {
    test('解析 sha256sum／shasum 的格式：兩個空白或 * 二進位模式，空行與註解略過', () {
      final a = 'A' * 64;
      final b = 'b' * 64;
      final sums = parseChecksums('# Securibit 1.2.0\n$a  $_zip\r\n\n$b *securibit_1.2.0_amd64.deb\nnot a line\n${'c' * 63}  short.apk\n');
      expect(sums, {_zip: 'a' * 64, 'securibit_1.2.0_amd64.deb': b});
      expect(checksumFor(sums, _zip), 'a' * 64);
      expect(checksumFor(sums, 'securibit-1.2.0-MACOS.zip'), 'a' * 64);
      expect(checksumFor(sums, 'other.zip'), isNull);
    });

    test('算出檔案的 SHA-256', () async {
      final dir = await Directory.systemTemp.createTemp('securibit-sum');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/a.bin')..writeAsStringSync('abc');
      expect(await sha256OfFile(file), 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
    });
  });

  group('下載與驗證', () {
    late Directory root;
    late _FakeInstaller installer;
    late _Server server;
    final prompts = <String>[];

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      root = await Directory.systemTemp.createTemp('securibit-update');
      installer = _FakeInstaller(root);
      server = _Server();
      prompts.clear();
    });
    tearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });

    UpdateController controller({String current = '1.1.9', String feedUrl = '', List<Duration> retryDelays = const []}) {
      final updates = UpdateController(
        repo: 'Securibit/Securibit-APP',
        feedUrl: feedUrl,
        target: _mac,
        installer: installer,
        client: server.client,
        readVersion: () async => current,
        retryDelays: retryDelays,
      );
      updates.onPrompt = (release) => prompts.add('${updates.status.name} ${release.version}');
      return updates;
    }

    test('查到新版就下載，檢查碼相同才解開，準備好後提示並在結束時安裝', () async {
      final updates = controller();
      await updates.load();
      final progress = <double?>[];
      updates.addListener(() => progress.add(updates.progress));
      expect((await updates.check())?.version.toString(), '1.2.0');
      expect(updates.status, UpdateStatus.downloading);
      await _settle(updates);
      expect(updates.status, UpdateStatus.ready);
      expect(progress, contains(1.0));
      expect(installer.prepared.single, endsWith('/1.2.0/$_zip'));
      expect(installer.armed.single, endsWith('/1.2.0'));
      expect(prompts, ['ready 1.2.0']);
      expect(server.requests.where((u) => u.endsWith('SHA256SUMS.txt')), hasLength(1));

      final outcome = await updates.install();
      expect(outcome.result, InstallResult.started);
      expect(installer.installed.single, endsWith(_zip));
      expect(updates.status, UpdateStatus.installing);
    });

    test('檢查碼不符：丟掉檔案、不解開也不安裝，之後重新下載', () async {
      server.sums = '${'f' * 64}  $_zip\n';
      final updates = controller();
      await updates.load();
      await updates.check();
      await _settle(updates);
      expect(updates.status, UpdateStatus.retrying);
      expect(installer.prepared, isEmpty);
      expect(prompts, isEmpty);
      expect(File('${root.path}/1.2.0/$_zip').existsSync(), isFalse);
      expect((await updates.install()).result, InstallResult.failed);
      expect(installer.installed, isEmpty);

      // 重試次數用完：下一次檢查重新下載，這次檢查碼對了
      server.sums = null;
      await updates.check();
      await _settle(updates);
      expect(updates.status, UpdateStatus.ready);
    });

    test('下載失敗時安靜地重試', () async {
      server.failuresLeft = 2;
      final updates = controller(retryDelays: const [Duration(milliseconds: 1), Duration(milliseconds: 1), Duration(milliseconds: 1)]);
      await updates.load();
      await updates.check();
      for (var i = 0; i < 400 && updates.status != UpdateStatus.ready; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(updates.status, UpdateStatus.ready);
      expect(server.downloads, 3);
      expect(prompts, ['ready 1.2.0']);
    });

    test('沒有檢查碼清單、清單裡沒有這個檔案、沒有 .zip：不下載，提示用瀏覽器下載', () async {
      for (final setup in <void Function()>[
        () => server.assets = [_zip],
        () => server.sums = '${'a' * 64}  other.zip\n',
        () => server.assets = ['Securibit-1.2.0-macos.dmg', 'SHA256SUMS.txt'],
      ]) {
        server = _Server();
        setup();
        prompts.clear();
        final updates = controller();
        await updates.load();
        await updates.check();
        await _settle(updates);
        expect(updates.status, UpdateStatus.available);
        expect(updates.manualReason, contains('瀏覽器'));
        expect(server.downloads, 0);
        expect(prompts, ['available 1.2.0']);
      }
    });

    test('這台不能替換（例如從磁碟映像檔執行）：說明原因，不下載', () async {
      installer.supportResult = const InstallSupport.manual('請先把 Securibit 移到「應用程式」資料夾');
      final updates = controller();
      await updates.load();
      await updates.check();
      await _settle(updates);
      expect(updates.status, UpdateStatus.available);
      expect(updates.manualReason, '請先把 Securibit 移到「應用程式」資料夾');
      expect(server.downloads, 0);
    });

    test('解開的內容不對（不是 Securibit、版本不符）：不重試，改用瀏覽器下載', () async {
      installer.prepareError = const UpdatePrepareException('下載的版本和說明不符');
      final updates = controller();
      await updates.load();
      await updates.check();
      await _settle(updates);
      expect(updates.status, UpdateStatus.available);
      expect(updates.manualReason, '下載的版本和說明不符，請用瀏覽器下載');
    });

    test('上次下載好的直接用，不重新下載；按「稍後」後每小時的自動檢查再提示', () async {
      final first = controller();
      await first.load();
      await first.check();
      await _settle(first);
      expect(server.downloads, 1);

      prompts.clear();
      final reopened = controller();
      await reopened.load();
      await reopened.checkAutomatically();
      await _settle(reopened);
      expect(reopened.status, UpdateStatus.ready);
      expect(server.downloads, 1);
      expect(prompts, ['ready 1.2.0']);

      await reopened.checkAutomatically();
      expect(prompts, ['ready 1.2.0', 'ready 1.2.0']);
      expect(server.downloads, 1);
    });

    test('下載好的檔案被換掉：安裝前發現，重新下載', () async {
      final updates = controller();
      await updates.load();
      await updates.check();
      await _settle(updates);
      File('${root.path}/1.2.0/$_zip').writeAsStringSync('被換掉了');
      final outcome = await updates.install();
      expect(outcome.result, InstallResult.failed);
      expect(installer.installed, isEmpty);
      await _settle(updates);
      expect(updates.status, UpdateStatus.ready);
      expect(server.downloads, 2);
    });

    test('更新完開 App 時清掉舊版本的檔案，比目前新的留著', () async {
      Directory('${root.path}/1.1.9').createSync(recursive: true);
      Directory('${root.path}/1.2.0').createSync(recursive: true);
      Directory('${root.path}/1.3.0').createSync(recursive: true);
      await controller(current: '1.2.0').load();
      expect(root.listSync().map((e) => e.uri.pathSegments.where((s) => s.isNotEmpty).last), ['1.3.0']);
    });

    test('只接受 https；測試用的 UPDATE_FEED_URL 指到本機時才允許 http', () async {
      final client = MockClient((request) async {
        final url = request.url.toString();
        if (url == _feed || url == 'http://127.0.0.1:8000/latest.json') {
          return http.Response.bytes(
            utf8.encode(jsonEncode({
              ..._releaseJson('v1.2.0', []),
              'assets': [
                {'name': _zip, 'browser_download_url': 'http://127.0.0.1:8000/$_zip'},
                {'name': 'SHA256SUMS.txt', 'browser_download_url': 'http://127.0.0.1:8000/SHA256SUMS.txt'},
              ],
            })),
            200,
          );
        }
        if (url.endsWith('SHA256SUMS.txt')) return http.Response('${_hex(utf8.encode('zip'))}  $_zip\n', 200);
        return http.Response('zip', 200);
      });
      UpdateController make(String feedUrl) => UpdateController(
            repo: 'Securibit/Securibit-APP',
            feedUrl: feedUrl,
            target: _mac,
            installer: installer,
            client: client,
            readVersion: () async => '1.1.9',
            retryDelays: const [],
          );

      final github = make('');
      await github.load();
      await github.check();
      await _settle(github);
      expect(github.status, UpdateStatus.retrying);

      await root.delete(recursive: true);
      await root.create();
      final local = make('http://127.0.0.1:8000/latest.json');
      await local.load();
      expect(local.enabled, isTrue);
      expect(local.usesTestFeed, isTrue);
      await local.check();
      await _settle(local);
      expect(local.status, UpdateStatus.ready);
    });

    test('UPDATE_REPO 留空但有測試用網址時也能檢查', () async {
      final updates = UpdateController(
        repo: '',
        feedUrl: 'http://127.0.0.1:8000/latest.json',
        target: _mac,
        installer: installer,
        client: server.client,
        readVersion: () async => '1.1.9',
      );
      await updates.load();
      expect(updates.enabled, isTrue);
      expect((await updates.check())?.version.toString(), '1.2.0');
      expect(server.requests.first, 'http://127.0.0.1:8000/latest.json');
      await _settle(updates);
    });
  });

  group('安裝方式的判斷', () {
    test('macOS：從執行檔找到目前的 .app，不寫死 /Applications', () {
      expect(InstallLocation.macAppBundle('/Applications/securibit.app/Contents/MacOS/securibit'), '/Applications/securibit.app');
      expect(InstallLocation.macAppBundle('/Users/a/My Apps/Securibit.app/Contents/MacOS/securibit'), '/Users/a/My Apps/Securibit.app');
      expect(InstallLocation.macAppBundle('/usr/local/bin/securibit'), isNull);
    });

    test('macOS：App Translocation、唯讀的磁碟映像檔要先搬到「應用程式」；沒有權限時用瀏覽器下載', () {
      const translocated = '/private/var/folders/xx/T/AppTranslocation/1234-ABCD/d/securibit.app';
      expect(InstallLocation.macIsTranslocated(translocated), isTrue);
      expect(InstallLocation.macBlockedReason(translocated, writable: true), contains('應用程式'));
      expect(InstallLocation.macBlockedReason('/Volumes/Securibit 1.2.0/securibit.app', writable: false), contains('應用程式'));
      expect(InstallLocation.macBlockedReason('/Applications/securibit.app', writable: false), contains('沒有權限'));
      expect(InstallLocation.macBlockedReason('/Applications/securibit.app', writable: true), isNull);
      // 外接硬碟上可以寫入的照樣更新
      expect(InstallLocation.macBlockedReason('/Volumes/Data/securibit.app', writable: true), isNull);
    });

    test('Linux：/usr、/opt 底下或 dpkg 清單裡的是 .deb，其他是 .tar.gz', () {
      expect(InstallLocation.linuxIsDeb('/opt/securibit/securibit', dpkgList: ''), isTrue);
      expect(InstallLocation.linuxIsDeb('/usr/lib/securibit/securibit', dpkgList: ''), isTrue);
      expect(InstallLocation.linuxIsDeb('/home/a/Apps/securibit/securibit', dpkgList: ''), isFalse);
      expect(InstallLocation.linuxIsDeb('/srv/securibit/securibit', dpkgList: '/.\n/srv/securibit\n/srv/securibit/securibit\n'), isTrue);
      expect(InstallLocation.linuxBundleDir('/home/a/Apps/securibit/securibit'), '/home/a/Apps/securibit');
    });

    test('Windows：執行檔旁邊有 Inno Setup 的解除安裝程式（unins000.exe）的是安裝檔裝的，其他是免安裝版', () {
      const installed = r'C:\Users\a\AppData\Local\Programs\Securibit\securibit.exe';
      expect(InstallLocation.windowsIsSetup(installed, siblings: ['securibit.exe', 'flutter_windows.dll', 'unins000.exe', 'unins000.dat']), isTrue);
      // 重新安裝過幾次時 Inno Setup 會用下一個號碼；大小寫不拘
      expect(InstallLocation.windowsIsSetup(installed, siblings: ['securibit.exe', 'UNINS001.EXE']), isTrue);
      expect(InstallLocation.windowsIsSetup(r'D:\Tools\Securibit\securibit.exe', siblings: ['securibit.exe', 'flutter_windows.dll', 'data']), isFalse);
      expect(InstallLocation.windowsIsSetup(installed, siblings: ['unins000.dat', 'uninstall.exe']), isFalse);
    });

    test('Windows：安裝檔裝的自動安裝，免安裝版說明要用瀏覽器下載', () async {
      expect(UpdateInstaller.forTarget(const UpdateTarget(UpdatePlatform.windows, arch: 'x64', setup: true)), isA<WindowsSetupInstaller>());
      final portable = UpdateInstaller.forTarget(const UpdateTarget(UpdatePlatform.windows, arch: 'x64'));
      expect(portable, isA<BrowserOnlyInstaller>());
      final support = await portable.support();
      expect(support.auto, isFalse);
      expect(support.reason, windowsPortableReason);
      expect(await portable.workDir(), isNull);
    });

    test('Windows：安裝檔用靜默安裝的參數執行，裝好後自動打開（/UPDATE），記錄寫到指定的檔案', () {
      final args = windowsSetupArguments(log: r'C:\Users\a\AppData\Local\Securibit\update-install.log');
      expect(args, containsAllInOrder(['/SILENT', '/SUPPRESSMSGBOXES', '/NORESTART']));
      expect(args, containsAll(['/NOCANCEL', '/SP-', '/UPDATE']));
      expect(args.last, r'/LOG=C:\Users\a\AppData\Local\Securibit\update-install.log');
      // 不會跳出確認或重新開機的參數不能少；也不能是完全看不到進度的 /VERYSILENT
      expect(args, isNot(contains('/VERYSILENT')));
      final installer = WindowsSetupInstaller(executable: r'C:\Users\a\AppData\Local\Programs\Securibit\securibit.exe');
      expect(installer.actionLabel, '重新啟動並更新');
      expect(installer.exitsApp, isTrue);
    });

    test('Windows：下載的檔案放在 %LOCALAPPDATA%\\Securibit\\updates；沒有 LOCALAPPDATA 就不能自動安裝', () async {
      final installer = WindowsSetupInstaller(executable: r'C:\P\Securibit\securibit.exe', localAppData: r'C:\Users\a\AppData\Local');
      expect((await installer.workDir())?.path, r'C:\Users\a\AppData\Local\Securibit\updates');
      expect(await WindowsSetupInstaller(executable: r'C:\P\securibit.exe', localAppData: '').workDir(), isNull);
    });

    test('Windows：下載的安裝檔要是 Windows 執行檔（MZ 開頭）', () async {
      final dir = await Directory.systemTemp.createTemp('securibit-win');
      addTearDown(() => dir.delete(recursive: true));
      final release = AppRelease.fromJson(_releaseJson('v1.2.0', const []))!;
      final installer = WindowsSetupInstaller(executable: '${dir.path}/securibit.exe', localAppData: dir.path);
      final exe = File('${dir.path}/setup.exe')..writeAsBytesSync([0x4D, 0x5A, 0x90, 0x00]);
      await installer.prepare(exe, dir, release);
      final html = File('${dir.path}/error.html')..writeAsStringSync('<html>');
      await expectLater(installer.prepare(html, dir, release), throwsA(isA<UpdatePrepareException>()));
      final empty = File('${dir.path}/empty.exe')..writeAsBytesSync(const []);
      await expectLater(installer.prepare(empty, dir, release), throwsA(isA<UpdatePrepareException>()));
    });

    test('Windows：安裝的資料夾可以寫入才自動安裝', () async {
      final dir = await Directory.systemTemp.createTemp('securibit-win');
      addTearDown(() => dir.delete(recursive: true));
      final ok = WindowsSetupInstaller(executable: '${dir.path}${Platform.pathSeparator}securibit.exe', localAppData: dir.path);
      expect((await ok.support()).auto, isTrue);
      expect(dir.listSync(), isEmpty, reason: '檢查用的暫存檔要刪掉');
      final missing = WindowsSetupInstaller(executable: '${dir.path}${Platform.pathSeparator}none${Platform.pathSeparator}securibit.exe');
      expect((await missing.support()).reason, contains('沒有權限'));
    });

    test('按鈕名稱：.deb 與 Android 是「立即更新」，其他是「重新啟動並更新」', () {
      expect(MacAppInstaller(executable: '/Applications/securibit.app/Contents/MacOS/securibit').actionLabel, '重新啟動並更新');
      expect(LinuxBundleInstaller(executable: '/home/a/securibit/securibit').actionLabel, '重新啟動並更新');
      expect(LinuxDebInstaller(executable: '/opt/securibit/securibit').actionLabel, '立即更新');
      expect(AndroidApkInstaller().actionLabel, '立即更新');
    });

    test('macOS：可以寫入的位置能自動安裝，App Translocation 不行', () async {
      final dir = await Directory.systemTemp.createTemp('securibit-mac');
      addTearDown(() => dir.delete(recursive: true));
      Directory('${dir.path}/securibit.app/Contents/MacOS').createSync(recursive: true);
      final ok = MacAppInstaller(executable: '${dir.path}/securibit.app/Contents/MacOS/securibit', home: dir.path);
      expect((await ok.support()).auto, isTrue);
      expect((await ok.workDir())?.path, '${dir.path}/Library/Caches/com.bityo.securibit/updates');
      final translocated = MacAppInstaller(executable: '/private/var/folders/x/AppTranslocation/1/d/securibit.app/Contents/MacOS/securibit');
      expect((await translocated.support()).reason, contains('應用程式'));
      expect((await MacAppInstaller(executable: '/usr/local/bin/securibit').support()).auto, isFalse);
    }, skip: Platform.isWindows);
  });

  group('替換腳本', () {
    late Directory dir;
    setUp(() async => dir = await Directory.systemTemp.createTemp('securibit-helper'));
    tearDown(() async => dir.delete(recursive: true));

    // 已經結束的程序：跑一個馬上結束的 true，拿它的 PID
    Future<int> deadPid() async {
      final process = await Process.start('true', []);
      await process.exitCode;
      return process.pid;
    }

    Future<ProcessResult> run(String script, String newPath, String target) async {
      final file = File('${dir.path}/install.sh')..writeAsStringSync(script);
      return Process.run('/bin/sh', [file.path, '${await deadPid()}', newPath, target, '0', '${dir.path}/install.log']);
    }

    void makeApp(String path, String version) {
      Directory('$path/Contents').createSync(recursive: true);
      File('$path/Contents/version').writeAsStringSync(version);
    }

    test('Linux：等 App 結束後替換資料夾，成功才刪掉舊的', () async {
      final target = '${dir.path}/Apps dir/securibit';
      Directory(target).createSync(recursive: true);
      File('$target/securibit').writeAsStringSync('old');
      final staged = '${dir.path}/stage/app/securibit';
      Directory(staged).createSync(recursive: true);
      File('$staged/securibit').writeAsStringSync('new');

      final result = await run(linuxInstallScript, staged, target);
      expect(result.exitCode, 0);
      expect(File('$target/securibit').readAsStringSync(), 'new');
      expect(Directory(staged).existsSync(), isFalse);
      // 沒有留下暫存的名稱
      expect(Directory('${dir.path}/Apps dir').listSync().map((e) => e.uri.pathSegments.where((s) => s.isNotEmpty).last), ['securibit']);
      expect(File('${dir.path}/install.log').readAsStringSync(), contains('完成'));
    }, skip: _noShell);

    test('找不到新版或複製失敗時不動舊版', () async {
      final target = '${dir.path}/securibit';
      Directory(target).createSync();
      File('$target/securibit').writeAsStringSync('old');
      final result = await run(linuxInstallScript, '${dir.path}/missing', target);
      expect(result.exitCode, 1);
      expect(File('$target/securibit').readAsStringSync(), 'old');
      expect(Directory(dir.path).listSync().where((e) => e.path.contains('.securibit-update-')), isEmpty);
    }, skip: _noShell);

    test('同一份更新只跑一次', () async {
      final target = '${dir.path}/securibit';
      Directory(target).createSync();
      final staged = '${dir.path}/new';
      Directory(staged).createSync();
      Directory('$staged.lock').createSync();
      final result = await run(linuxInstallScript, staged, target);
      expect(result.exitCode, 0);
      expect(Directory(staged).existsSync(), isTrue);
      expect(File('${dir.path}/install.log').readAsStringSync(), contains('已經有另一個更新在跑'));
    }, skip: _noShell);

    test('macOS：用 ditto 換掉 .app（名稱照目前的，不一定是 securibit.app）', () async {
      final target = '${dir.path}/Applications/Securibit.app';
      makeApp(target, '1.1.9');
      final staged = '${dir.path}/stage/app/securibit.app';
      makeApp(staged, '1.2.0');
      final result = await run(macInstallScript, staged, target);
      expect(result.exitCode, 0, reason: File('${dir.path}/install.log').readAsStringSync());
      expect(File('$target/Contents/version').readAsStringSync(), '1.2.0');
      expect(Directory('${dir.path}/Applications').listSync(), hasLength(1));
    }, skip: !Platform.isMacOS);

    test('腳本不把路徑拼進內容（路徑用參數傳）', () {
      for (final script in [macInstallScript, linuxInstallScript]) {
        expect(script, startsWith('#!/bin/sh'));
        expect(script, contains('pid="\$1"; new="\$2"; target="\$3"; relaunch="\$4"; log="\$5"'));
        expect(script, isNot(contains('/Applications')));
      }
      expect(macInstallScript, contains('xattr -dr com.apple.quarantine'));
      expect(macInstallScript, contains('open "\$target"'));
    });
  });

  group('macOS 解開與檢查', () {
    late Directory dir;
    setUp(() async => dir = await Directory.systemTemp.createTemp('securibit-prepare'));
    tearDown(() async => dir.delete(recursive: true));

    // 做一個本機簽章（ad-hoc）的假 App，壓成和 Makefile 一樣的 zip
    Future<File> makeZip(String version, {String id = 'com.bityo.securibit'}) async {
      final app = Directory('${dir.path}/build/securibit.app/Contents/MacOS')..createSync(recursive: true);
      File('${app.path}/securibit').writeAsStringSync('#!/bin/sh\n');
      await Process.run('chmod', ['755', '${app.path}/securibit']);
      File('${dir.path}/build/securibit.app/Contents/Info.plist').writeAsStringSync('''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>$id</string>
<key>CFBundleExecutable</key><string>securibit</string>
<key>CFBundleShortVersionString</key><string>$version</string>
</dict></plist>''');
      final sign = await Process.run('codesign', ['--force', '--sign', '-', '${dir.path}/build/securibit.app']);
      expect(sign.exitCode, 0, reason: '${sign.stderr}');
      final zip = File('${dir.path}/$_zip');
      final ditto = await Process.run('ditto', ['-c', '-k', '--sequesterRsrc', '--keepParent', '${dir.path}/build/securibit.app', zip.path]);
      expect(ditto.exitCode, 0);
      Directory('${dir.path}/build').deleteSync(recursive: true);
      return zip;
    }

    final release = AppRelease.fromJson(_releaseJson('v1.2.0', [_zip]))!;

    test('解開後確認是同一個 App、版本相同、簽章完整', () async {
      final zip = await makeZip('1.2.0');
      final stage = Directory('${dir.path}/stage')..createSync();
      final installer = MacAppInstaller(executable: '${dir.path}/none/securibit.app/Contents/MacOS/securibit', home: dir.path);
      await installer.prepare(zip, stage, release);
      expect(await installer.isPrepared(stage), isTrue);
      expect(Directory('${stage.path}/app/securibit.app').existsSync(), isTrue);
    });

    test('版本不符或不是 Securibit 就不放', () async {
      final installer = MacAppInstaller(executable: '${dir.path}/none/securibit.app/Contents/MacOS/securibit', home: dir.path);
      for (final (index, make) in [() => makeZip('1.1.0'), () => makeZip('1.2.0', id: 'com.example.other')].indexed) {
        final zip = await make();
        final stage = Directory('${dir.path}/stage-$index')..createSync();
        await expectLater(installer.prepare(zip, stage, release), throwsA(isA<UpdatePrepareException>()));
        expect(await installer.isPrepared(stage), isFalse);
        zip.deleteSync();
      }
    });
  }, skip: !Platform.isMacOS);

  // 1.2.0 關掉 App Sandbox：鑰匙圈項目（登入 session、App 鎖定、離線快取、裝置金鑰）照舊讀得到，前提是查詢的條件不變。
  // 改成 data protection keychain、加 access group 或換 service 名稱，從 1.1.x 更新上來的人都會被登出
  test('macOS 鑰匙圈的查詢條件和 1.1.x 相同（傳統的登入鑰匙圈、沒有 access group、預設的 service）', () {
    final options = secureStore.mOptions.toMap();
    expect(options['useDataProtectionKeyChain'], 'false');
    expect(options.containsKey('groupId'), isFalse);
    expect(options['accountName'], 'flutter_secure_storage_service');
    expect(options['accessibility'], 'first_unlock_this_device');
    expect(options['synchronizable'], 'false');
  });

  testWidgets('下載好之後的提示：「新版本已準備好」，按鈕是「稍後」與「重新啟動並更新」', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final root = Directory.systemTemp.createTempSync('securibit-dialog');
    addTearDown(() => root.deleteSync(recursive: true));
    final server = _Server();
    final updates = UpdateController(
      repo: 'Securibit/Securibit-APP',
      target: _mac,
      installer: _FakeInstaller(root),
      client: server.client,
      readVersion: () async => '1.1.9',
    );
    await tester.runAsync(() async {
      await updates.load();
      await updates.check();
      await _settle(updates);
    });
    expect(updates.status, UpdateStatus.ready);
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.light),
      home: Builder(
        builder: (context) => TextButton(onPressed: () => showUpdatePrompt(context, updates, updates.latest!), child: const Text('open')),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('新版本已準備好，強烈建議更新'), findsOneWidget);
    expect(find.text('Securibit 1.2.0 已下載完成，目前是 1.1.9'), findsOneWidget);
    expect(find.text('自動更新', findRichText: true), findsOneWidget);
    expect(find.text('重新啟動並更新'), findsOneWidget);
    expect(find.text('用瀏覽器下載'), findsNothing);
    await tester.tap(find.text('稍後'));
    await tester.pumpAndSettle();
    expect(find.text('新版本已準備好，強烈建議更新'), findsNothing);
  });
}
