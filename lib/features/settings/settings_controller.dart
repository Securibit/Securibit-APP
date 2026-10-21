import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../menubar/mac_menu_bar.dart';

import 'lock/app_lock_controller.dart';
import 'screen_privacy.dart';

/*
 * App 的偏好設定，存在這台裝置：
 * 主題（預設跟隨系統）、隱藏驗證碼（同網站，所有群組共用）、允許截圖（手機預設不允許，macOS 預設允許）、App 鎖定，
 * 以及只有 macOS 有的「在選單列顯示」（預設打開）與「登入時自動開啟」（預設關閉）。
 * App 鎖定的設定存在安全儲存（見 AppLockController），這裡轉發它的變更通知。
 */
class SettingsController extends ChangeNotifier {
  SettingsController({AppLockController? appLock}) : appLock = appLock ?? AppLockController() {
    this.appLock.addListener(_onLockChanged);
  }

  static const _themeKey = 'securibit:theme';
  static const _hideKey = 'securibit:hideCodes';
  static const _screenshotKey = 'securibit:allowScreenshots';
  static const _menuBarKey = 'securibit:menuBar';
  static const _launchAtLoginKey = 'securibit:launchAtLogin';
  // 舊版只有生物辨識鎖定；現在生物辨識要搭配圖形或密碼，舊設定不再使用
  static const _legacyBiometricKey = 'securibit:biometricLock';

  final AppLockController appLock;

  ThemeMode themeMode = ThemeMode.system;
  bool hideCodes = false;
  bool allowScreenshots = ScreenPrivacy.allowByDefault;
  bool showInMenuBar = true;
  // 系統裡實際的狀態（使用者也可能在系統設定的「登入項目」改掉）
  LaunchAtLoginState launchAtLogin = LaunchAtLoginState.unsupported;

  SharedPreferences? _prefs;

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _prefs = prefs;
      themeMode = switch (prefs.getString(_themeKey)) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };
      hideCodes = prefs.getBool(_hideKey) ?? false;
      allowScreenshots = prefs.getBool(_screenshotKey) ?? ScreenPrivacy.allowByDefault;
      showInMenuBar = prefs.getBool(_menuBarKey) ?? true;
      if (prefs.containsKey(_legacyBiometricKey)) await prefs.remove(_legacyBiometricKey);
    } catch (_) {
      // 讀不到就用預設值
    }
    await appLock.load();
    _applyPrivacy();
    await _loadLaunchAtLogin();
  }

  // 以系統的登記狀態為準，存下來的值只是記錄
  Future<void> _loadLaunchAtLogin() async {
    if (!MacMenuBar.supported) return;
    launchAtLogin = await LaunchAtLogin.status();
    if (launchAtLogin != LaunchAtLoginState.unsupported) await _prefs?.setBool(_launchAtLoginKey, launchAtLogin.on);
  }

  void setThemeMode(ThemeMode mode) {
    themeMode = mode;
    notifyListeners();
    _prefs?.setString(_themeKey, mode.name);
  }

  void setHideCodes(bool hide) {
    hideCodes = hide;
    notifyListeners();
    _prefs?.setBool(_hideKey, hide);
  }

  void setAllowScreenshots(bool allow) {
    allowScreenshots = allow;
    notifyListeners();
    _prefs?.setBool(_screenshotKey, allow);
    _applyPrivacy();
  }

  void setShowInMenuBar(bool show) {
    showInMenuBar = show;
    notifyListeners();
    _prefs?.setBool(_menuBarKey, show);
  }

  /// 登記或取消登入時自動開啟；回傳錯誤訊息，成功為 null
  Future<String?> setLaunchAtLogin(bool enabled) async {
    try {
      launchAtLogin = await LaunchAtLogin.set(enabled);
    } on PlatformException catch (error) {
      launchAtLogin = await LaunchAtLogin.status();
      notifyListeners();
      return error.message ?? '無法變更登入項目';
    }
    notifyListeners();
    await _prefs?.setBool(_launchAtLoginKey, launchAtLogin.on);
    return null;
  }

  void _onLockChanged() {
    notifyListeners();
    _applyPrivacy();
  }

  // 不允許截圖或有設定鎖定時，多工畫面都不顯示內容
  void _applyPrivacy() => ScreenPrivacy.apply(blockCapture: !allowScreenshots, hideInSwitcher: !allowScreenshots || appLock.enabled);

  @override
  void dispose() {
    appLock.removeListener(_onLockChanged);
    super.dispose();
  }
}
