import 'dart:io' show Platform;

// 依平台決定功能：桌面用三欄版面、相機掃描只在手機、生物辨識在 iOS / Android / macOS
class AppPlatform {
  AppPlatform._();

  static bool get isMobile => Platform.isIOS || Platform.isAndroid;
  static bool get isDesktop => Platform.isMacOS || Platform.isLinux || Platform.isWindows;
  static bool get canScanQr => isMobile;
  static bool get canUseBiometrics => Platform.isIOS || Platform.isAndroid || Platform.isMacOS;

  // 給網站登入紀錄解析的裝置名稱（網站用 user-agent 判斷系統）
  static String get userAgent {
    if (Platform.isIOS) return 'SecuribitApp (iPhone; iOS)';
    if (Platform.isAndroid) return 'SecuribitApp (Linux; Android)';
    if (Platform.isMacOS) return 'SecuribitApp (Macintosh; Mac OS X)';
    if (Platform.isWindows) return 'SecuribitApp (Windows)';
    return 'SecuribitApp (X11; Linux)';
  }
}
