import 'dart:ffi' show Abi;
import 'dart:io' show Platform;

import 'app_version.dart';
import 'install_location.dart';

/// GitHub Release 裡的一個附件
class ReleaseAsset {
  const ReleaseAsset({required this.name, required this.url});

  final String name;
  // browser_download_url：瀏覽器打開就會下載
  final String url;
}

/*
 * GitHub Releases API（/releases/latest）回傳的一個版本：標籤、說明（Markdown）、網頁與附件。
 * latest 本來就不含草稿與預先發行，這裡再擋一次；標籤看不懂是什麼版本的也不算。
 */
class AppRelease {
  const AppRelease({required this.tag, required this.version, required this.notes, required this.pageUrl, required this.assets});

  final String tag;
  final AppVersion version;
  final String notes;
  // html_url：找不到這個平台的檔案時打開這頁
  final String pageUrl;
  final List<ReleaseAsset> assets;

  /// 附件檔名裡的版本：標籤去掉 v（v0.3.0 → 0.3.0），和 Makefile 產出的檔名一致
  String get fileVersion => tag.trim().replaceFirst(RegExp('^[vV]'), '');

  static AppRelease? fromJson(Object? json) {
    if (json is! Map) return null;
    if (json['draft'] == true || json['prerelease'] == true) return null;
    final tag = json['tag_name'];
    final page = json['html_url'];
    if (tag is! String || page is! String) return null;
    final version = AppVersion.tryParse(tag);
    if (version == null) return null;
    final body = json['body'];
    return AppRelease(
      tag: tag,
      version: version,
      notes: body is String ? body : '',
      pageUrl: page,
      assets: [
        for (final asset in json['assets'] is List ? json['assets'] as List : const [])
          if (asset is Map && asset['name'] is String && asset['browser_download_url'] is String)
            ReleaseAsset(name: asset['name'] as String, url: asset['browser_download_url'] as String),
      ],
    );
  }

  /// 這個平台用瀏覽器下載的網址：依序找 target 列出的檔名，都沒有就打開 Release 頁面
  String downloadUrl(UpdateTarget target) => _find(target.assetNames)?.url ?? pageUrl;

  /// App 自己下載、驗證後安裝的檔案（macOS 的 .zip、Linux 的 .deb 或 .tar.gz、Android 的 APK、Windows 的安裝檔）；這一版沒有就是 null
  ReleaseAsset? installAsset(UpdateTarget target) => _find(target.installAssetNames);

  /// 每個 Release 附的檢查碼清單（SHA256SUMS.txt，sha256sum 的格式）；沒有附就不能自動安裝
  ReleaseAsset? get checksumsAsset {
    for (final asset in assets) {
      final name = asset.name.toLowerCase();
      if (name == 'sha256sums.txt' || name == 'sha256sums') return asset;
    }
    return null;
  }

  // 依序找 names 列出的檔名（不分大小寫；檔名裡的版本也接受帶 v 的寫法）
  ReleaseAsset? _find(List<String> Function(String version) names) {
    for (final version in [fileVersion, 'v$fileVersion']) {
      for (final name in names(version)) {
        for (final asset in assets) {
          if (asset.name.toLowerCase() == name.toLowerCase()) return asset;
        }
      }
    }
    return null;
  }
}

enum UpdatePlatform { macos, linux, android, windows }

/*
 * 要找哪個安裝檔，檔名對照 Makefile 的產出：
 * - macOS：用瀏覽器下載時先找 Securibit-<版本>-macos.dmg，其次 .zip；App 自己更新時只用 .zip（ditto 解開就是 .app）
 * - Linux：.deb 安裝的（見 InstallLocation.linuxIsDeb）先找 securibit_<版本>_<amd64|arm64>.deb，
 *   其他（.tar.gz 解開的）找 Securibit-<版本>-linux-<x64|arm64>.tar.gz；App 自己更新時 .deb 只用 .deb、其他只用 .tar.gz
 * - Android：securibit-<版本>-<arm64-v8a|armeabi-v7a|x86_64>.apk，其次不分處理器的 securibit-<版本>.apk
 * - Windows：用安裝檔裝的（見 InstallLocation.windowsIsSetup）找 Securibit-<版本>-windows-x64-setup.exe，其次免安裝版的
 *   Securibit-<版本>-windows-x64.zip；免安裝版反過來先找 .zip。App 自己更新時只用安裝檔，免安裝版只能用瀏覽器下載
 * 認不得的處理器架構沒有檔名可以找，直接開 Release 頁面。iOS 只能走 App Store / TestFlight，不檢查更新。
 */
class UpdateTarget {
  const UpdateTarget(this.platform, {this.arch, this.deb = false, this.setup = false});

  final UpdatePlatform platform;
  // Linux、Windows：x64、arm64；Android：APK 的 ABI 名稱
  final String? arch;
  // Linux 是用 .deb 安裝的
  final bool deb;
  // Windows 是用安裝檔（setup.exe）裝的；false 是免安裝版（.zip 解開的資料夾）
  final bool setup;

  /// 目前執行中的平台；iOS 與其他平台回傳 null
  static UpdateTarget? current() {
    if (Platform.isMacOS) return const UpdateTarget(UpdatePlatform.macos);
    if (Platform.isLinux) {
      return UpdateTarget(UpdatePlatform.linux, arch: linuxArch(Abi.current()), deb: InstallLocation.linuxIsDeb(Platform.resolvedExecutable));
    }
    if (Platform.isAndroid) return UpdateTarget(UpdatePlatform.android, arch: androidAbi(Abi.current()));
    if (Platform.isWindows) {
      return UpdateTarget(UpdatePlatform.windows, arch: windowsArch(Abi.current()), setup: InstallLocation.windowsIsSetup(Platform.resolvedExecutable));
    }
    return null;
  }

  // 目前只建 x64；ARM 的 Windows 用模擬執行 x64 版，Abi 也會是 windowsX64
  static String? windowsArch(Abi abi) => switch (abi) {
        Abi.windowsX64 => 'x64',
        _ => null,
      };

  static String? linuxArch(Abi abi) => switch (abi) {
        Abi.linuxX64 => 'x64',
        Abi.linuxArm64 => 'arm64',
        _ => null,
      };

  static String? androidAbi(Abi abi) => switch (abi) {
        Abi.androidArm64 => 'arm64-v8a',
        Abi.androidArm => 'armeabi-v7a',
        Abi.androidX64 => 'x86_64',
        _ => null,
      };

  /// App 自己下載安裝時要找的檔名（依優先順序）
  List<String> installAssetNames(String version) {
    final arch = this.arch;
    switch (platform) {
      case UpdatePlatform.macos:
        return ['Securibit-$version-macos.zip'];
      case UpdatePlatform.linux:
        if (arch == null) return const [];
        if (deb) return ['securibit_${version}_${arch == 'x64' ? 'amd64' : arch}.deb'];
        return ['Securibit-$version-linux-$arch.tar.gz'];
      case UpdatePlatform.android:
        return [if (arch != null) 'securibit-$version-$arch.apk', 'securibit-$version.apk'];
      case UpdatePlatform.windows:
        if (arch == null || !setup) return const [];
        return [_windowsSetup(version, arch)];
    }
  }

  static String _windowsSetup(String version, String arch) => 'Securibit-$version-windows-$arch-setup.exe';
  static String _windowsZip(String version, String arch) => 'Securibit-$version-windows-$arch.zip';

  /// 用瀏覽器下載時要找的檔名（依優先順序）
  List<String> assetNames(String version) {
    final arch = this.arch;
    switch (platform) {
      case UpdatePlatform.macos:
        return ['Securibit-$version-macos.dmg', 'Securibit-$version-macos.zip'];
      case UpdatePlatform.linux:
        if (arch == null) return const [];
        final tarball = 'Securibit-$version-linux-$arch.tar.gz';
        if (!deb) return [tarball];
        return ['securibit_${version}_${arch == 'x64' ? 'amd64' : arch}.deb', tarball];
      case UpdatePlatform.android:
        return [if (arch != null) 'securibit-$version-$arch.apk', 'securibit-$version.apk'];
      case UpdatePlatform.windows:
        if (arch == null) return const [];
        final names = [_windowsSetup(version, arch), _windowsZip(version, arch)];
        return setup ? names : names.reversed.toList();
    }
  }
}

/// Release 說明（Markdown）拆成的一段
enum NoteBlockType { heading, paragraph, bullet, table }

class NoteBlock {
  const NoteBlock(this.type, {this.text = '', this.depth = 0, this.marker = '•', this.rows = const []});

  final NoteBlockType type;
  // 標題、段落、清單項目的文字（行內的粗體、程式碼、連結由畫面處理）
  final String text;
  // 清單的縮排層數
  final int depth;
  // 清單記號：「•」或「1.」
  final String marker;
  // 表格：第一列是表頭（分隔線已拿掉）
  final List<List<String>> rows;
}

/// 更新提示裡不顯示的段落：「下載」表格和提示的「立即更新」重複（會自動挑這個平台的檔案）
const _hiddenSections = {'下載'};

/// 把 Release 說明拆成標題、段落、清單與表格（GitHub 會寫的那幾種），註解與「下載」段落拿掉
List<NoteBlock> releaseNoteBlocks(String markdown) {
  final lines = markdown.replaceAll('\r\n', '\n').replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '').split('\n');
  final blocks = <NoteBlock>[];
  final paragraph = <String>[];
  final table = <List<String>>[];
  // 正在略過的段落標題層級
  int? skipping;

  void flush() {
    if (paragraph.isNotEmpty) {
      blocks.add(NoteBlock(NoteBlockType.paragraph, text: paragraph.join(' ')));
      paragraph.clear();
    }
    if (table.isNotEmpty) {
      blocks.add(NoteBlock(NoteBlockType.table, rows: [...table]));
      table.clear();
    }
  }

  for (final raw in lines) {
    final line = raw.trimRight();
    final heading = RegExp(r'^\s{0,3}(#{1,6})\s+(.*?)\s*#*$').firstMatch(line);
    if (heading != null) {
      flush();
      final level = heading[1]!.length;
      final title = heading[2]!.trim();
      if (skipping != null && level > skipping) continue;
      skipping = _hiddenSections.contains(title) ? level : null;
      if (skipping == null) blocks.add(NoteBlock(NoteBlockType.heading, text: title, depth: level));
      continue;
    }
    if (skipping != null) continue;

    if (line.trimLeft().startsWith('|')) {
      if (paragraph.isNotEmpty) flush();
      // 表頭下面的分隔線（|---|:---:|）
      if (RegExp(r'^\s*\|?[\s:|-]+$').hasMatch(line) && line.contains('-')) continue;
      var cells = line.trim().split('|').map((c) => c.trim()).toList();
      if (cells.isNotEmpty && cells.first.isEmpty) cells = cells.sublist(1);
      if (cells.isNotEmpty && cells.last.isEmpty) cells = cells.sublist(0, cells.length - 1);
      table.add(cells);
      continue;
    }
    if (table.isNotEmpty) flush();

    final bullet = RegExp(r'^(\s*)([-*+]|\d+[.)])\s+(.*)$').firstMatch(line);
    if (bullet != null) {
      flush();
      final marker = bullet[2]!;
      blocks.add(NoteBlock(
        NoteBlockType.bullet,
        text: bullet[3]!,
        depth: bullet[1]!.replaceAll('\t', '  ').length ~/ 2,
        marker: RegExp(r'^\d').hasMatch(marker) ? '${marker.substring(0, marker.length - 1)}.' : '•',
      ));
      continue;
    }
    if (line.trim().isEmpty) {
      flush();
      continue;
    }
    paragraph.add(line.trim());
  }
  flush();
  return blocks;
}
