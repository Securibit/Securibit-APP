import 'dart:io' show Platform;

// 依平台決定功能：桌面用三欄版面、相機掃描在 iOS / Android / macOS、從圖片讀 QR Code 另外加上 Linux 與 Windows、生物辨識在 iOS / Android / macOS
class AppPlatform {
  AppPlatform._();

  static bool get isMobile => Platform.isIOS || Platform.isAndroid;
  static bool get isDesktop => Platform.isMacOS || Platform.isLinux || Platform.isWindows;
  static bool get canScanQr => isMobile || Platform.isMacOS;
  // 從圖片讀 QR Code：iOS / Android / macOS 用 mobile_scanner 的 analyzeImage，Linux、Windows 用 Rust 核心（import_sources.dart）
  static bool get canReadQrImage => isMobile || Platform.isMacOS || usesRustQrImage;
  // mobile_scanner 沒有 Linux、Windows 版，從圖片讀 QR Code 改用 Rust 核心
  static bool get usesRustQrImage => Platform.isLinux || Platform.isWindows;
  // 生物辨識：Windows Hello（local_auth_windows）還沒接，Windows 先只用密碼、PIN 或圖形解鎖
  static bool get canUseBiometrics => Platform.isIOS || Platform.isAndroid || Platform.isMacOS;

  /// Linux 的 Flutter 引擎不會依字元向系統要備援字型（只掃 /usr/share/fonts，系統預設字型多半沒有中文），
  /// 不指定的話中文全部顯示成方塊。依序找各發行版常見的繁體中文字型，最後才用簡體、日文的 CJK 字型。
  /// 其他平台系統會自己找，不用指定
  static List<String>? get fontFamilyFallback => Platform.isLinux ? linuxCjkFonts : null;

  static const linuxCjkFonts = [
    'Noto Sans CJK TC',
    'Noto Sans TC',
    'Source Han Sans TC',
    'Source Han Sans TW',
    'WenQuanYi Zen Hei',
    'WenQuanYi Micro Hei',
    'AR PL UMing TW',
    'Droid Sans Fallback',
    'Noto Sans CJK SC',
    'Noto Sans CJK JP',
  ];

  // 給網站登入紀錄解析的裝置名稱（網站用 user-agent 判斷系統）
  static String get userAgent {
    if (Platform.isIOS) return 'SecuribitApp (iPhone; iOS)';
    if (Platform.isAndroid) return 'SecuribitApp (Linux; Android)';
    if (Platform.isMacOS) return 'SecuribitApp (Macintosh; Mac OS X)';
    if (Platform.isWindows) return 'SecuribitApp (Windows)';
    return 'SecuribitApp (X11; Linux)';
  }
}
