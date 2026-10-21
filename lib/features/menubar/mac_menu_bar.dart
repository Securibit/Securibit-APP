import 'dart:io' show Platform;

import 'package:flutter/services.dart';

/*
 * macOS 選單列與登入時自動開啟的原生介面（channel：securibit/menubar，原生端見 macos/Runner/MenuBarController.swift）。
 * 其他平台沒有這些功能，全部直接略過。
 */
class MacMenuBar {
  MacMenuBar._();

  static const channel = MethodChannel('securibit/menubar');

  static bool get supported => Platform.isMacOS;

  /// 打開或關掉選單列圖示；關掉時關視窗就結束 App
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
  // 已登記，但要到系統設定的「登入項目」允許
  requiresApproval;

  bool get on => this == enabled || this == requiresApproval;

  static LaunchAtLoginState fromName(String? name) =>
      LaunchAtLoginState.values.firstWhere((s) => s.name == name, orElse: () => LaunchAtLoginState.unsupported);
}

class LaunchAtLogin {
  LaunchAtLogin._();

  static Future<LaunchAtLoginState> status() async {
    if (!MacMenuBar.supported) return LaunchAtLoginState.unsupported;
    try {
      return LaunchAtLoginState.fromName(await MacMenuBar.channel.invokeMethod<String>('launchAtLoginStatus'));
    } on MissingPluginException {
      return LaunchAtLoginState.unsupported;
    } on PlatformException {
      return LaunchAtLoginState.unsupported;
    }
  }

  /// 登記或取消；回傳之後的狀態，失敗時丟出 PlatformException（message 是原因）
  static Future<LaunchAtLoginState> set(bool enabled) async {
    if (!MacMenuBar.supported) return LaunchAtLoginState.unsupported;
    try {
      final name = await MacMenuBar.channel.invokeMethod<String>('setLaunchAtLogin', {'enabled': enabled});
      return LaunchAtLoginState.fromName(name);
    } on MissingPluginException {
      return LaunchAtLoginState.unsupported;
    }
  }

  /// 打開系統設定的「登入項目」
  static Future<void> openSystemSettings() async {
    if (!MacMenuBar.supported) return;
    try {
      await MacMenuBar.channel.invokeMethod<void>('openLoginItemsSettings');
    } on MissingPluginException {
      // 測試環境沒有原生端
    } on PlatformException {
      // 打不開就算了
    }
  }
}
