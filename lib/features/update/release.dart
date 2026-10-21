import 'dart:ffi' show Abi;
import 'dart:io' show Platform;

import 'app_version.dart';

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

  /// 這個平台該下載的網址：依序找 target 列出的檔名（不分大小寫；檔名裡的版本也接受帶 v 的寫法），都沒有就打開 Release 頁面
  String downloadUrl(UpdateTarget target) {
    for (final version in [fileVersion, 'v$fileVersion']) {
      for (final name in target.assetNames(version)) {
        for (final asset in assets) {
          if (asset.name.toLowerCase() == name.toLowerCase()) return asset.url;
        }
      }
    }
    return pageUrl;
  }
}

enum UpdatePlatform { macos, linux, android }

/*
 * 要找哪個安裝檔，檔名對照 Makefile 的產出：
 * - macOS：Securibit-<版本>-macos.dmg，其次 .zip
 * - Linux：.deb 安裝的（程式在 /opt/securibit）先找 securibit_<版本>_<amd64|arm64>.deb，
 *   其他（.tar.gz 解開的）找 Securibit-<版本>-linux-<x64|arm64>.tar.gz
 * - Android：securibit-<版本>-<arm64-v8a|armeabi-v7a|x86_64>.apk，其次不分處理器的 securibit-<版本>.apk
 * 認不得的處理器架構沒有檔名可以找，直接開 Release 頁面。iOS 只能走 App Store / TestFlight，不檢查更新。
 */
class UpdateTarget {
  const UpdateTarget(this.platform, {this.arch, this.deb = false});

  final UpdatePlatform platform;
  // Linux：x64、arm64；Android：APK 的 ABI 名稱
  final String? arch;
  // Linux 是用 .deb 安裝的
  final bool deb;

  // .deb 把程式裝在這裡（tool/linux/package_deb.sh），/usr/bin/securibit 只是指過來的連結
  static const debInstallDir = '/opt/securibit/';

  /// 目前執行中的平台；iOS 與其他平台回傳 null
  static UpdateTarget? current() {
    if (Platform.isMacOS) return const UpdateTarget(UpdatePlatform.macos);
    if (Platform.isLinux) {
      return UpdateTarget(UpdatePlatform.linux, arch: linuxArch(Abi.current()), deb: Platform.resolvedExecutable.startsWith(debInstallDir));
    }
    if (Platform.isAndroid) return UpdateTarget(UpdatePlatform.android, arch: androidAbi(Abi.current()));
    return null;
  }

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

  /// 依優先順序列出要找的檔名
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
    }
  }
}

/// Release 說明是 Markdown，這裡只轉成好讀的純文字：去掉標題井號、粗體、程式碼記號，連結只留文字，清單改成「・」
String plainReleaseNotes(String markdown) {
  var text = markdown.replaceAll('\r\n', '\n').replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '');
  text = text
      .split('\n')
      .map((line) => line
          .replaceFirst(RegExp(r'^\s{0,3}#{1,6}\s+'), '')
          .replaceFirstMapped(RegExp(r'^(\s*)[-*+]\s+'), (m) => '${m[1]}・')
          .replaceAll(RegExp(r'\s+#+\s*$'), '')
          .trimRight())
      .join('\n');
  text = text
      .replaceAllMapped(RegExp(r'!?\[([^\]]*)\]\([^)]*\)'), (m) => m[1]!)
      .replaceAllMapped(RegExp(r'(\*\*|__)(.+?)\1'), (m) => m[2]!)
      .replaceAllMapped(RegExp(r'~~(.+?)~~'), (m) => m[1]!)
      .replaceAll('`', '')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n');
  return text.trim();
}
