import 'dart:io' show FileSystemException, Platform;

import 'package:flutter/services.dart';

import 'linux_autostart.dart';

/*
 * 桌面常駐圖示（macOS 選單列、Linux 與 Windows 的系統匣）與登入時自動開啟的原生介面。
 * 三個平台共用同一個 channel（securibit/menubar）與同一份選單內容：
 * - macOS：原生端見 macos/Runner/MenuBarController.swift（NSStatusItem + NSMenu）
 * - Linux：原生端見 linux/runner/tray.cc（AppIndicator + GTK 選單）；登入時自動開啟直接在 Dart 寫 autostart 檔
 * - Windows：原生端見 windows/runner/tray.cpp（Shell_NotifyIcon + TrackPopupMenu）；
 *   登入時自動開啟是登錄檔的 Run 值（windows/runner/launch_at_login.cpp）
 * 其他平台沒有這些功能，全部直接略過。
 */

/// 常駐圖示的平台差異（純資料，方便測試）
enum TrayPlatform {
  macos,
  linux,
  windows,
  none;

  static TrayPlatform get current {
    if (Platform.isMacOS) return macos;
    if (Platform.isLinux) return linux;
    if (Platform.isWindows) return windows;
    return none;
  }

  bool get supported => this != none;

  /// 設定與說明裡的叫法：macOS 是「選單列」，Linux、Windows 是「系統匣」
  String get place => this == macos ? '選單列' : '系統匣';

  /// 選單開著時才知道要更新的平台以外，主視窗藏起來時也要持續更新選單內容。
  /// Linux 的 AppIndicator 選單由面板畫，不是每個桌面都會通知「選單要打開了」，
  /// 所以視窗藏著時（只能從系統匣看驗證碼）每秒送完整內容。
  /// macOS、Windows 的選單由 App 自己打開，打開前一定會先要最新內容（menuWillOpen），不用每秒送
  bool get refreshWhileHidden => this == linux;

  /// 登入時自動開啟由原生端處理（macOS 的 SMAppService、Windows 的登錄檔）；Linux 在 Dart 寫 autostart 檔
  bool get nativeLaunchAtLogin => this == macos || this == windows;
}

/// 設定頁「選單列／系統匣」區塊的說明（一則一行）
List<String> trayNotes(
  TrayPlatform platform, {
  required bool showInTray,
  required bool showCodes,
  required LaunchAtLoginState launch,
}) {
  final place = platform.place;
  return [
    if (!showInTray)
      '關閉視窗就會結束 Securibit'
    else
      switch (platform) {
        TrayPlatform.linux => '關閉視窗後 Securibit 會留在系統匣，點圖示就能複製驗證碼；選「結束 Securibit」才會結束。桌面沒有系統匣時關閉視窗一樣會結束',
        TrayPlatform.windows => '關閉視窗後 Securibit 會留在系統匣，點圖示就能複製驗證碼；選「結束 Securibit」才會結束',
        _ => '關閉視窗後 Securibit 會留在選單列，點圖示就能複製驗證碼；按 ⌘Q 才會結束',
      },
    if (showInTray && !showCodes) '$place的選單不列出驗證碼，只能打開 Securibit 或結束',
    if (platform == TrayPlatform.linux) 'GNOME 要先安裝 AppIndicator 擴充功能才看得到系統匣圖示；KDE、XFCE、Cinnamon 可以直接使用',
    if (platform == TrayPlatform.windows && showInTray) '圖示可能收在工作列右下角的「^」裡，可以把它拖到工作列上，一直顯示',
    if (launch == LaunchAtLoginState.unsupported && platform == TrayPlatform.macos) '登入時自動開啟需要 macOS 13 以上',
    if (launch == LaunchAtLoginState.requiresApproval)
      platform == TrayPlatform.windows
          ? '已在「設定 › 應用程式 › 啟動」關掉 Securibit，要在那裡打開才會自動開啟'
          : '要到「系統設定 › 一般 › 登入項目」允許 Securibit 才會自動開啟',
  ];
}

class DesktopTray {
  DesktopTray._();

  static const channel = MethodChannel('securibit/menubar');

  static bool get supported => TrayPlatform.current.supported;

  /// 設定與說明裡的叫法（見 TrayPlatform.place）
  static String get place => TrayPlatform.current.place;

  /// 主視窗藏起來時要不要每秒送完整內容（見 TrayPlatform.refreshWhileHidden）
  static bool get refreshWhileHidden => TrayPlatform.current.refreshWhileHidden;

  /// 叫回主視窗並切到前景（瀏覽器登入完成、點連結打開時、從系統匣叫回來）
  static Future<void> showWindow() async {
    if (!supported) return;
    try {
      await channel.invokeMethod<void>('showWindow');
    } on MissingPluginException {
      // 測試環境沒有原生端
    } on PlatformException {
      // 叫不回來就讓使用者自己切回來
    }
  }

  /// 打開或關掉常駐圖示；關掉時關視窗就結束 App
  static Future<void> setEnabled(bool enabled) async {
    if (!supported) return;
    try {
      await channel.invokeMethod<void>('setEnabled', {'enabled': enabled});
    } on MissingPluginException {
      // 測試環境沒有原生端
    } on PlatformException {
      // 原生端出錯就維持原狀
    }
  }

  /// 把算好的選單內容交給原生端（只有顯示用的文字）
  static Future<void> update(Map<String, Object?> model) async {
    if (!supported) return;
    try {
      await channel.invokeMethod<void>('update', model);
    } on MissingPluginException {
      // 測試環境沒有原生端
    } on PlatformException {
      // 下次再送
    }
  }
}

// 登入時自動開啟的狀態：unsupported 是 macOS 13 以前（沒有 SMAppService）或其他平台
enum LaunchAtLoginState {
  unsupported,
  enabled,
  disabled,
  // 已登記，但要到系統設定允許：macOS 的「登入項目」，Windows 是在「設定 › 應用程式 › 啟動」或工作管理員被關掉
  requiresApproval;

  bool get on => this == enabled || this == requiresApproval;

  static LaunchAtLoginState fromName(String? name) =>
      LaunchAtLoginState.values.firstWhere((s) => s.name == name, orElse: () => LaunchAtLoginState.unsupported);
}

/*
 * 登入時自動開啟：macOS 用 SMAppService（原生端），Windows 寫登錄檔的 Run 值（原生端，帶 --hidden 直接藏在系統匣），
 * Linux 寫 ~/.config/autostart 的 .desktop 檔（見 LinuxAutostart）。
 */
class LaunchAtLogin {
  LaunchAtLogin._();

  static Future<LaunchAtLoginState> status() async {
    if (Platform.isLinux) return _linuxState(await LinuxAutostart.current().refresh());
    if (!TrayPlatform.current.nativeLaunchAtLogin) return LaunchAtLoginState.unsupported;
    try {
      return LaunchAtLoginState.fromName(await DesktopTray.channel.invokeMethod<String>('launchAtLoginStatus'));
    } on MissingPluginException {
      return LaunchAtLoginState.unsupported;
    } on PlatformException {
      return LaunchAtLoginState.unsupported;
    }
  }

  /// 登記或取消；回傳之後的狀態，失敗時丟出 PlatformException（message 是原因）
  static Future<LaunchAtLoginState> set(bool enabled) async {
    if (Platform.isLinux) {
      try {
        await LinuxAutostart.current().setEnabled(enabled);
      } on FileSystemException catch (error) {
        throw PlatformException(code: 'launch-at-login', message: '無法寫入自動啟動設定：${error.osError?.message ?? error.message}');
      }
      return _linuxState(await LinuxAutostart.current().isEnabled());
    }
    if (!TrayPlatform.current.nativeLaunchAtLogin) return LaunchAtLoginState.unsupported;
    try {
      final name = await DesktopTray.channel.invokeMethod<String>('setLaunchAtLogin', {'enabled': enabled});
      return LaunchAtLoginState.fromName(name);
    } on MissingPluginException {
      return LaunchAtLoginState.unsupported;
    }
  }

  static LaunchAtLoginState _linuxState(bool enabled) => enabled ? LaunchAtLoginState.enabled : LaunchAtLoginState.disabled;

  /// 打開系統設定的「登入項目」（macOS）或「設定 › 應用程式 › 啟動」（Windows）
  static Future<void> openSystemSettings() async {
    if (!TrayPlatform.current.nativeLaunchAtLogin) return;
    try {
      await DesktopTray.channel.invokeMethod<void>('openLoginItemsSettings');
    } on MissingPluginException {
      // 測試環境沒有原生端
    } on PlatformException {
      // 打不開就算了
    }
  }
}
