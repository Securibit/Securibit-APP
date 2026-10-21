import 'dart:io' show FileSystemException, Platform;

import 'package:flutter/services.dart';

import 'linux_autostart.dart';

/*
 * 桌面常駐圖示（macOS 選單列、Linux 系統匣）與登入時自動開啟的原生介面。
 * 兩個平台共用同一個 channel（securibit/menubar）與同一份選單內容：
 * - macOS：原生端見 macos/Runner/MenuBarController.swift（NSStatusItem + NSMenu）
 * - Linux：原生端見 linux/runner/tray.cc（AppIndicator + GTK 選單）；登入時自動開啟直接在 Dart 寫 autostart 檔
 * 其他平台沒有這些功能，全部直接略過。
 */
class DesktopTray {
  DesktopTray._();

  static const channel = MethodChannel('securibit/menubar');

  static bool get supported => Platform.isMacOS || Platform.isLinux;

  /// 設定與說明裡的叫法：macOS 是「選單列」，Linux 是「系統匣」
  static String get place => Platform.isLinux ? '系統匣' : '選單列';

  /// 選單開著時才知道要更新的平台（macOS）以外，主視窗藏起來時也要持續更新選單內容。
  /// Linux 的 AppIndicator 選單由面板畫，不是每個桌面都會通知「選單要打開了」，
  /// 所以視窗藏著時（只能從系統匣看驗證碼）每秒送完整內容
  static bool get refreshWhileHidden => Platform.isLinux;

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
  // 已登記，但要到系統設定的「登入項目」允許（只有 macOS）
  requiresApproval;

  bool get on => this == enabled || this == requiresApproval;

  static LaunchAtLoginState fromName(String? name) =>
      LaunchAtLoginState.values.firstWhere((s) => s.name == name, orElse: () => LaunchAtLoginState.unsupported);
}

/*
 * 登入時自動開啟：macOS 用 SMAppService（原生端），Linux 寫 ~/.config/autostart 的 .desktop 檔（見 LinuxAutostart）。
 */
class LaunchAtLogin {
  LaunchAtLogin._();

  static Future<LaunchAtLoginState> status() async {
    if (Platform.isLinux) return _linuxState(await LinuxAutostart.current().refresh());
    if (!Platform.isMacOS) return LaunchAtLoginState.unsupported;
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
    if (!Platform.isMacOS) return LaunchAtLoginState.unsupported;
    try {
      final name = await DesktopTray.channel.invokeMethod<String>('setLaunchAtLogin', {'enabled': enabled});
      return LaunchAtLoginState.fromName(name);
    } on MissingPluginException {
      return LaunchAtLoginState.unsupported;
    }
  }

  static LaunchAtLoginState _linuxState(bool enabled) => enabled ? LaunchAtLoginState.enabled : LaunchAtLoginState.disabled;

  /// 打開系統設定的「登入項目」（只有 macOS）
  static Future<void> openSystemSettings() async {
    if (!Platform.isMacOS) return;
    try {
      await DesktopTray.channel.invokeMethod<void>('openLoginItemsSettings');
    } on MissingPluginException {
      // 測試環境沒有原生端
    } on PlatformException {
      // 打不開就算了
    }
  }
}
