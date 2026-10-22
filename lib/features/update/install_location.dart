import 'dart:io';

/*
 * 這份 App 裝在哪裡、是用什麼方式裝的（判斷規則是純函式，方便測試；檢查權限、執行指令在 update_installer.dart）：
 * - macOS：執行檔在 <某處>/securibit.app/Contents/MacOS/ 裡，要替換的就是那個 .app（不寫死 /Applications）。
 *   從 App Translocation（下載後沒搬就直接打開，系統把 App 放到唯讀的隨機路徑）或磁碟映像檔執行時不能替換
 * - Linux：執行檔在 /usr 或 /opt 底下、或列在 dpkg 的安裝清單裡的是 .deb（tool/linux/package_deb.sh 裝到 /opt/securibit），
 *   其他的是 .tar.gz 解開的資料夾（securibit/，裡面直接是執行檔）
 * - Windows：執行檔旁邊有 Inno Setup 的解除安裝程式（unins000.exe，tool/windows/securibit.iss）的是安裝檔裝的
 *   （預設在 %LOCALAPPDATA%\Programs\Securibit），其他的是免安裝版（.zip 解開的資料夾）
 */
class InstallLocation {
  InstallLocation._();

  // dpkg 記錄 securibit 套件裝了哪些檔案
  static const dpkgFileList = '/var/lib/dpkg/info/securibit.list';

  /// macOS：…/securibit.app/Contents/MacOS/securibit → …/securibit.app；不在 .app 裡回傳 null
  static String? macAppBundle(String executable) => RegExp(r'^(/.+\.app)/Contents/MacOS/[^/]+$').firstMatch(executable)?[1];

  /// macOS：系統把 App 隔離到唯讀的暫存位置（App Translocation）
  static bool macIsTranslocated(String bundle) => bundle.contains('/AppTranslocation/');

  /// macOS：不能替換時告訴使用者怎麼做；可以替換時回傳 null
  static String? macBlockedReason(String bundle, {required bool writable}) {
    if (macIsTranslocated(bundle) || (!writable && bundle.startsWith('/Volumes/'))) {
      return '請先把 Securibit 移到「應用程式」資料夾，再重新打開，之後就能自動更新';
    }
    if (!writable) return '沒有權限替換 $bundle，請用瀏覽器下載新版';
    return null;
  }

  /// Linux：是不是用 .deb 安裝的。dpkgList 是 dpkg 安裝清單的內容（沒給就讀系統的）
  static bool linuxIsDeb(String executable, {String? dpkgList}) {
    if (executable.startsWith('/usr/') || executable.startsWith('/opt/')) return true;
    final list = dpkgList ?? _readOrNull(dpkgFileList);
    return list != null && list.split('\n').any((line) => line.trim() == executable);
  }

  /// Linux：.tar.gz 解開的資料夾（執行檔所在的資料夾）
  static String linuxBundleDir(String executable) => File(executable).parent.path;

  /// Windows：是不是用安裝檔裝的。siblings 是執行檔所在資料夾裡的檔名（沒給就讀那個資料夾）
  static bool windowsIsSetup(String executable, {Iterable<String>? siblings}) {
    final names = siblings ?? _listNames(File(executable).parent.path);
    final uninstaller = RegExp(r'^unins\d{3}\.exe$', caseSensitive: false);
    return names.any(uninstaller.hasMatch);
  }

  static Iterable<String> _listNames(String dir) {
    try {
      return Directory(dir).listSync().map((e) => e.path.split(RegExp(r'[\\/]')).last);
    } catch (_) {
      return const [];
    }
  }

  static String? _readOrNull(String path) {
    try {
      return File(path).readAsStringSync();
    } catch (_) {
      return null;
    }
  }
}
