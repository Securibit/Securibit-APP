import 'dart:async';
import 'dart:io';
import 'dart:ui' show AppExitType;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'app_version.dart';
import 'helper_scripts.dart';
import 'install_location.dart';
import 'release.dart';

/// 這台裝置能不能自己下載安裝更新；不能時 reason 告訴使用者怎麼做（只能用瀏覽器下載）
class InstallSupport {
  const InstallSupport.auto() : reason = null;
  const InstallSupport.manual(this.reason);

  final String? reason;

  bool get auto => reason == null;
}

/// 安裝的結果
enum InstallResult {
  // 已經交給系統或替換程式（macOS、Linux、Windows 接著會結束 App；Android 跳出系統的安裝畫面）
  started,
  // Android：還沒允許 Securibit 安裝應用程式
  needsPermission,
  // 使用者取消（Linux 的 pkexec 授權視窗）
  cancelled,
  failed,
}

class InstallOutcome {
  const InstallOutcome(this.result, [this.message]);

  final InstallResult result;
  // 失敗的原因（顯示給使用者）
  final String? message;
}

/// 解開或檢查下載的檔案失敗（檔案內容不對，重新下載也一樣）：不重試，改用瀏覽器下載
class UpdatePrepareException implements Exception {
  const UpdatePrepareException(this.message);

  final String message;

  @override
  String toString() => message;
}

/*
 * 各平台的安裝方式：
 * - macOS（MacAppInstaller）：.zip 用 ditto 解開，檢查 Bundle ID、版本與簽章的 Team ID 都對，
 *   按「重新啟動並更新」或結束 App 時由原生端（AppUpdate.swift）在 applicationWillTerminate 啟動替換腳本
 * - Linux .tar.gz（LinuxBundleInstaller）：解開後由替換腳本等 App 結束再換掉資料夾、重新打開
 * - Linux .deb（LinuxDebInstaller）：pkexec apt-get install，裝好後重新打開
 * - Android（AndroidApkInstaller）：交給系統的安裝畫面（FileProvider + ACTION_VIEW，MainActivity.kt）
 * - Windows 安裝檔裝的（WindowsSetupInstaller）：App 結束後由新版的 setup.exe 靜默安裝，裝好自動打開；
 *   免安裝版（.zip 解開的）不能自動更新，用瀏覽器下載
 * 下載與檢查碼由 UpdateController 處理，這裡只管「放在哪」「能不能裝」「怎麼裝」。
 */
abstract class UpdateInstaller {
  const UpdateInstaller();

  /// 依平台挑安裝方式；不支援自動安裝的回傳 BrowserOnlyInstaller
  static UpdateInstaller forTarget(UpdateTarget? target) {
    if (target == null) return const BrowserOnlyInstaller();
    switch (target.platform) {
      case UpdatePlatform.macos:
        return MacAppInstaller();
      case UpdatePlatform.linux:
        return target.deb ? LinuxDebInstaller() : LinuxBundleInstaller();
      case UpdatePlatform.android:
        return AndroidApkInstaller();
      case UpdatePlatform.windows:
        return target.setup ? WindowsSetupInstaller() : const BrowserOnlyInstaller(windowsPortableReason);
    }
  }

  /// 這個版本的 App 要不要檢查更新（Google Play 版交給商店，不檢查）
  Future<bool> selfUpdateAllowed() async => true;

  /// 下載的檔案與解開的新版放在這裡，每個版本一個子資料夾；拿不到時是 null（不能自動安裝）
  Future<Directory?> workDir();

  Future<InstallSupport> support();

  /// 下載好之後的按鈕
  String get actionLabel => '重新啟動並更新';

  /// 按了之後 App 會自己結束（macOS、Linux、Windows）；Android 跳出系統的安裝畫面，App 還開著
  bool get exitsApp => true;

  /// 安裝要等一陣子時先告訴使用者（Linux .deb 要等授權與 apt）
  String? get installingMessage => null;

  /// 解開或檢查下載好的檔案（已經通過檢查碼），放在 stage 裡
  Future<void> prepare(File download, Directory stage, AppRelease release) async {}

  /// stage 裡已經有解開好的新版（上次開著時下載的）
  Future<bool> isPrepared(Directory stage) async => true;

  /// 下載好之後：使用者結束 App 時順便安裝（macOS）
  Future<void> armOnQuit(Directory stage) async {}

  Future<InstallOutcome> install(Directory stage, File download);

  /// Android：打開「安裝不明應用程式」的設定
  Future<void> openPermissionSettings() async {}
}

/// 不能自動安裝（iOS 不會用到；沒有對應的平台時用瀏覽器下載）
class BrowserOnlyInstaller extends UpdateInstaller {
  const BrowserOnlyInstaller([this.reason]);

  final String? reason;

  @override
  Future<Directory?> workDir() async => null;

  @override
  Future<InstallSupport> support() async => InstallSupport.manual(reason);

  @override
  Future<InstallOutcome> install(Directory stage, File download) async => const InstallOutcome(InstallResult.failed);
}

const _channel = MethodChannel('securibit/update');

// 用 test -w 檢查目前的使用者能不能寫（access(2)，會算群組與 ACL）
Future<bool> _writable(String path) async {
  try {
    final result = await Process.run('/bin/sh', ['-c', 'test -w "\$1"', 'sh', path]);
    return result.exitCode == 0;
  } catch (_) {
    return false;
  }
}

Future<void> _run(String executable, List<String> arguments, String failure) async {
  final ProcessResult result;
  try {
    result = await Process.run(executable, arguments);
  } catch (e) {
    throw UpdatePrepareException('$failure（$e）');
  }
  if (result.exitCode != 0) throw UpdatePrepareException('$failure（${'${result.stderr}'.trim()}）');
}

// 替換腳本的記錄：放在 updates/ 外面（更新好後開 App 時會清掉 updates/ 裡的舊版本，記錄要留著查問題）
String _installLog(Directory stage) => '${stage.parent.parent.path}/update-install.log';

// 把 extract 改名成 stage/app（解開到一半的不會被當成解開好的）
Future<Directory> _promote(Directory extract, Directory stage) async {
  final app = Directory('${stage.path}/app');
  if (await app.exists()) await app.delete(recursive: true);
  return extract.rename(app.path);
}

/*
 * macOS：替換目前執行中的 .app（看 Platform.resolvedExecutable，不寫死 /Applications）。
 * 從 App Translocation 或磁碟映像檔執行、或沒有權限寫入時不替換，提示使用者先搬到「應用程式」或用瀏覽器下載。
 * 下載的檔案放在 ~/Library/Caches/com.bityo.securibit/updates/（關掉 App Sandbox 後就是使用者自己的 Library）。
 */
class MacAppInstaller extends UpdateInstaller {
  MacAppInstaller({String? executable, String? home})
      : bundle = InstallLocation.macAppBundle(executable ?? Platform.resolvedExecutable),
        _home = home ?? Platform.environment['HOME'];

  final String? bundle;
  final String? _home;

  @override
  Future<Directory?> workDir() async {
    final home = _home;
    if (home == null || home.isEmpty) return null;
    return Directory('$home/Library/Caches/com.bityo.securibit/updates');
  }

  @override
  Future<InstallSupport> support() async {
    final bundle = this.bundle;
    if (bundle == null) return const InstallSupport.manual('找不到 Securibit 的位置，請用瀏覽器下載新版');
    // 要能在 .app 所在的資料夾建立與改名，.app 本身也要能移動
    final writable = !InstallLocation.macIsTranslocated(bundle) && await _writable(File(bundle).parent.path) && await _writable(bundle);
    final reason = InstallLocation.macBlockedReason(bundle, writable: writable);
    return reason == null ? const InstallSupport.auto() : InstallSupport.manual(reason);
  }

  // 解開的新版：stage/app/<名稱>.app
  Future<Directory?> _newApp(Directory stage) async {
    final app = Directory('${stage.path}/app');
    if (!await app.exists()) return null;
    final apps = await app.list().where((e) => e is Directory && e.path.endsWith('.app')).cast<Directory>().toList();
    return apps.length == 1 ? apps.single : null;
  }

  @override
  Future<bool> isPrepared(Directory stage) async => await _newApp(stage) != null;

  @override
  Future<void> prepare(File download, Directory stage, AppRelease release) async {
    final extract = Directory('${stage.path}/extract');
    if (await extract.exists()) await extract.delete(recursive: true);
    await extract.create(recursive: true);
    await _run('/usr/bin/ditto', ['-x', '-k', download.path, extract.path], '無法解開下載的檔案');
    final apps = await extract.list().where((e) => e is Directory && e.path.endsWith('.app')).toList();
    if (apps.length != 1) throw const UpdatePrepareException('下載的檔案裡沒有 Securibit');
    final app = apps.single.path;

    // 是同一個 App、版本和 Release 相同
    final id = await _plistValue('$app/Contents/Info.plist', 'CFBundleIdentifier');
    final currentId = bundle == null ? null : await _plistValue('$bundle/Contents/Info.plist', 'CFBundleIdentifier');
    if (id == null || id != (currentId ?? 'com.bityo.securibit')) throw const UpdatePrepareException('下載的不是 Securibit');
    final version = AppVersion.tryParse(await _plistValue('$app/Contents/Info.plist', 'CFBundleShortVersionString'));
    if (version != release.version) throw const UpdatePrepareException('下載的版本和說明不符');

    // 簽章完整，而且和目前的 App 是同一個開發者（目前的 App 沒有 Team ID 時，例如本機自己簽的，就不比）
    await _run('/usr/bin/codesign', ['--verify', '--strict', app], '新版的簽章不完整');
    final currentTeam = bundle == null ? null : await _teamId(bundle!);
    if (currentTeam != null && await _teamId(app) != currentTeam) throw const UpdatePrepareException('新版的簽章和目前的 App 不同');

    await _promote(extract, stage);
  }

  static Future<String?> _plistValue(String plist, String key) async {
    try {
      final result = await Process.run('/usr/libexec/PlistBuddy', ['-c', 'Print :$key', plist]);
      return result.exitCode == 0 ? '${result.stdout}'.trim() : null;
    } catch (_) {
      return null;
    }
  }

  // codesign -dv 印在 stderr 的 TeamIdentifier；沒有簽或沒有 Team（not set）時是 null
  static Future<String?> _teamId(String app) async {
    try {
      final result = await Process.run('/usr/bin/codesign', ['-dv', '--verbose=2', app]);
      final team = RegExp(r'^TeamIdentifier=(.+)$', multiLine: true).firstMatch('${result.stderr}')?[1]?.trim();
      return team == null || team == 'not set' ? null : team;
    } catch (_) {
      return null;
    }
  }

  // 把替換腳本交給原生端，App 結束時（applicationWillTerminate）啟動
  Future<bool> _arm(Directory stage, {required bool relaunch}) async {
    final target = bundle;
    final app = await _newApp(stage);
    if (target == null || app == null) return false;
    final script = File('${stage.path}/install.sh');
    await script.writeAsString(macInstallScript);
    try {
      await _channel.invokeMethod<void>('arm', {
        'script': script.path,
        'arguments': ['$pid', app.path, target, relaunch ? '1' : '0', _installLog(stage)],
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  // 開發時（flutter run）結束 App 不替換：不然會把 build/ 裡的 Debug 版換成下載的正式版
  @override
  Future<void> armOnQuit(Directory stage) async {
    if (kDebugMode) return;
    await _arm(stage, relaunch: false);
  }

  @override
  Future<InstallOutcome> install(Directory stage, File download) async {
    if (!await _arm(stage, relaunch: true)) return const InstallOutcome(InstallResult.failed, '無法啟動更新程式');
    try {
      await _channel.invokeMethod<void>('quit');
    } catch (_) {
      return const InstallOutcome(InstallResult.failed, '無法結束 App，請手動結束後再打開');
    }
    return const InstallOutcome(InstallResult.started);
  }
}

// Linux：下載的檔案放在 $XDG_CACHE_HOME/securibit/updates（預設 ~/.cache）
Directory? _linuxWorkDir() {
  final env = Platform.environment;
  final cache = env['XDG_CACHE_HOME'];
  final base = cache != null && cache.startsWith('/') ? cache : (env['HOME'] == null ? null : '${env['HOME']}/.cache');
  return base == null ? null : Directory('$base/securibit/updates');
}

// Linux、Windows：結束 App（Linux 系統匣常駐時關視窗只是藏起來，所以直接請引擎結束）；引擎沒反應時強制結束
Future<void> _exitDesktopApp() async {
  Timer(const Duration(seconds: 3), () => exit(0));
  try {
    await ServicesBinding.instance.exitApplication(AppExitType.required);
  } catch (_) {
    exit(0);
  }
}

/// Linux .tar.gz：替換解開的 securibit/ 資料夾（要有寫入權限，沒有時用瀏覽器下載）
class LinuxBundleInstaller extends UpdateInstaller {
  LinuxBundleInstaller({String? executable}) : bundleDir = InstallLocation.linuxBundleDir(executable ?? Platform.resolvedExecutable);

  final String bundleDir;

  @override
  Future<Directory?> workDir() async => _linuxWorkDir();

  @override
  Future<InstallSupport> support() async {
    if (await _writable(File(bundleDir).parent.path) && await _writable(bundleDir)) return const InstallSupport.auto();
    return InstallSupport.manual('沒有權限替換 $bundleDir，請用瀏覽器下載新版');
  }

  Directory _newBundle(Directory stage) => Directory('${stage.path}/app/securibit');

  @override
  Future<bool> isPrepared(Directory stage) => File('${_newBundle(stage).path}/securibit').exists();

  @override
  Future<void> prepare(File download, Directory stage, AppRelease release) async {
    final extract = Directory('${stage.path}/extract');
    if (await extract.exists()) await extract.delete(recursive: true);
    await extract.create(recursive: true);
    await _run('tar', ['-xzf', download.path, '-C', extract.path], '無法解開下載的檔案');
    // build.sh 打包的 .tar.gz 解開是 securibit/，裡面直接是執行檔
    if (!await File('${extract.path}/securibit/securibit').exists()) throw const UpdatePrepareException('下載的檔案裡沒有 Securibit');
    await _promote(extract, stage);
  }

  @override
  Future<InstallOutcome> install(Directory stage, File download) async {
    final script = File('${stage.path}/install.sh');
    try {
      await script.writeAsString(linuxInstallScript);
      await Process.start(
        '/bin/sh',
        [script.path, '$pid', _newBundle(stage).path, bundleDir, '1', _installLog(stage)],
        mode: ProcessStartMode.detached,
      );
    } catch (_) {
      return const InstallOutcome(InstallResult.failed, '無法啟動更新程式');
    }
    unawaited(_exitDesktopApp());
    return const InstallOutcome(InstallResult.started);
  }
}

/// Linux .deb：用 pkexec（系統的管理員授權視窗）執行 apt-get install，裝好後重新打開
class LinuxDebInstaller extends UpdateInstaller {
  LinuxDebInstaller({String? executable}) : executable = executable ?? Platform.resolvedExecutable;

  final String executable;

  @override
  String get actionLabel => '立即更新';

  @override
  String get installingMessage => '正在安裝更新，請在授權視窗輸入密碼';

  @override
  Future<Directory?> workDir() async => _linuxWorkDir();

  @override
  Future<InstallSupport> support() async => const InstallSupport.auto();

  @override
  Future<void> prepare(File download, Directory stage, AppRelease release) async {
    // 有 dpkg-deb 時確認是 securibit 套件（Debian／Ubuntu 一定有）
    try {
      final result = await Process.run('dpkg-deb', ['-f', download.path, 'Package']);
      if (result.exitCode == 0 && '${result.stdout}'.trim() != 'securibit') throw const UpdatePrepareException('下載的不是 Securibit 的套件');
    } on ProcessException {
      // 沒有 dpkg-deb 就不檢查
    }
  }

  static Future<String?> _which(String name) async {
    for (final dir in ['/usr/bin', '/bin', '/usr/sbin', '/sbin']) {
      if (await File('$dir/$name').exists()) return '$dir/$name';
    }
    return null;
  }

  @override
  Future<InstallOutcome> install(Directory stage, File download) async {
    final pkexec = await _which('pkexec');
    if (pkexec == null) return const InstallOutcome(InstallResult.failed, '找不到 pkexec，無法取得安裝需要的管理員權限');
    final apt = await _which('apt-get');
    final dpkg = await _which('dpkg');
    if (apt == null && dpkg == null) return const InstallOutcome(InstallResult.failed, '找不到 apt-get 或 dpkg');
    final ProcessResult result;
    try {
      // apt-get 會順便裝新版需要的相依套件；沒有 apt 的系統才直接用 dpkg -i
      result = await Process.run(pkexec, apt != null ? [apt, 'install', '-y', download.path] : [dpkg!, '-i', download.path]);
    } catch (e) {
      return InstallOutcome(InstallResult.failed, '無法執行 pkexec（$e）');
    }
    return _finish(result);
  }

  Future<InstallOutcome> _finish(ProcessResult result) async {
    // pkexec：126 是關掉授權視窗或沒有授權，127 是授權失敗
    if (result.exitCode == 126 || result.exitCode == 127) {
      return const InstallOutcome(InstallResult.cancelled, '沒有取得管理員權限，這次沒有安裝');
    }
    if (result.exitCode != 0) {
      final detail = '${result.stderr}'.trim().split('\n').where((l) => l.trim().isNotEmpty).lastOrNull;
      return InstallOutcome(InstallResult.failed, '安裝失敗${detail == null ? '' : '：$detail'}');
    }
    // 裝好了：等這個程序結束再打開新版
    final relaunch = await File('/usr/bin/securibit').exists() ? '/usr/bin/securibit' : executable;
    try {
      await Process.start('/bin/sh', ['-c', linuxRelaunchScript, 'sh', '$pid', relaunch], mode: ProcessStartMode.detached);
    } catch (_) {
      // 打不開就讓使用者自己開
    }
    unawaited(_exitDesktopApp());
    return const InstallOutcome(InstallResult.started);
  }
}

/*
 * Android（GitHub 版）：APK 下載到 App 的快取資料夾（cacheDir/updates，FileProvider 分享給系統安裝程式），
 * 交給系統的安裝畫面。第一次要使用者允許「安裝不明應用程式」。
 * Google Play 版（-Pdistribution=play）的 manifest 沒有 REQUEST_INSTALL_PACKAGES，原生端回報不能自我更新，整個檢查更新關掉。
 */
class AndroidApkInstaller extends UpdateInstaller {
  @override
  String get actionLabel => '立即更新';

  @override
  bool get exitsApp => false;

  // TODO(play): Google Play 版之後接 Play In-App Updates（com.google.android.play:app-update），由商店下載與安裝；這次先整個關掉
  @override
  Future<bool> selfUpdateAllowed() async {
    try {
      return await _channel.invokeMethod<bool>('selfUpdate') ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<Directory?> workDir() async {
    try {
      final path = await _channel.invokeMethod<String>('updatesDir');
      return path == null ? null : Directory(path);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<InstallSupport> support() async => const InstallSupport.auto();

  @override
  Future<InstallOutcome> install(Directory stage, File download) async {
    try {
      if (await _channel.invokeMethod<bool>('canInstall') != true) return const InstallOutcome(InstallResult.needsPermission);
      final ok = await _channel.invokeMethod<bool>('install', {'path': download.path});
      return ok == true ? const InstallOutcome(InstallResult.started) : const InstallOutcome(InstallResult.failed, '無法打開系統的安裝畫面');
    } catch (e) {
      return InstallOutcome(InstallResult.failed, '無法打開系統的安裝畫面（$e）');
    }
  }

  @override
  Future<void> openPermissionSettings() async {
    try {
      await _channel.invokeMethod<void>('openInstallSettings');
    } catch (_) {
      // 打不開設定就算了，使用者可以再按一次
    }
  }
}

/// Windows 免安裝版：不知道使用者把資料夾放在哪、會不會被其他程式鎖住，不自己替換
const windowsPortableReason = '免安裝版不會自動更新，請用瀏覽器下載新版；改用安裝檔安裝之後就能自動更新';

/// Windows 執行安裝檔的參數：不問問題、不能取消、不重新開機，裝好後自動打開新版（/UPDATE，見 tool/windows/securibit.iss）。
/// 安裝檔會先等目前的 App 結束（互斥鎖），所以可以先啟動它再結束 App
List<String> windowsSetupArguments({required String log}) => ['/SILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/NOCANCEL', '/SP-', '/UPDATE', '/LOG=$log'];

/*
 * Windows（安裝檔裝的，每個使用者各自裝在 %LOCALAPPDATA%\Programs\Securibit，不需要系統管理員）：
 * 下載的 setup.exe 放在 %LOCALAPPDATA%\Securibit\updates，按「重新啟動並更新」時啟動它（脫離 App 的程序）再結束 App；
 * 安裝檔等 App 結束後靜默安裝，裝好再打開新版。App 自己下載的檔案沒有「從網路下載」的標記，不會跳 SmartScreen。
 */
class WindowsSetupInstaller extends UpdateInstaller {
  WindowsSetupInstaller({String? executable, String? localAppData})
      : installDir = File(executable ?? Platform.resolvedExecutable).parent.path,
        _localAppData = localAppData ?? Platform.environment['LOCALAPPDATA'];

  final String installDir;
  final String? _localAppData;

  @override
  Future<Directory?> workDir() async {
    final base = _localAppData;
    if (base == null || base.isEmpty) return null;
    return Directory('$base\\Securibit\\updates');
  }

  // 安裝的資料夾要能寫（每個使用者各自安裝的一定可以；有人用系統管理員裝到 Program Files 時就不行，安裝檔會要求權限）
  @override
  Future<InstallSupport> support() async {
    final probe = File('$installDir${Platform.pathSeparator}.securibit-update-check-$pid');
    try {
      await probe.writeAsString('');
      await probe.delete();
      return const InstallSupport.auto();
    } catch (_) {
      return InstallSupport.manual('沒有權限更新 $installDir，請用瀏覽器下載新版');
    }
  }

  // 至少要是 Windows 的執行檔（MZ 開頭）；內容已經和 SHA256SUMS.txt 比對過
  @override
  Future<void> prepare(File download, Directory stage, AppRelease release) async {
    try {
      final head = await download.openRead(0, 2).expand((b) => b).toList();
      if (head.length == 2 && head[0] == 0x4D && head[1] == 0x5A) return;
    } catch (_) {
      // 讀不到就當作不是
    }
    throw const UpdatePrepareException('下載的不是 Securibit 的安裝檔');
  }

  @override
  Future<InstallOutcome> install(Directory stage, File download) async {
    try {
      await Process.start(download.path, windowsSetupArguments(log: _installLog(stage)), mode: ProcessStartMode.detached);
    } catch (_) {
      return const InstallOutcome(InstallResult.failed, '無法啟動安裝程式');
    }
    unawaited(_exitDesktopApp());
    return const InstallOutcome(InstallResult.started);
  }
}
