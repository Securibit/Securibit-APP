import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'lock/app_lock_controller.dart';
import 'screen_privacy.dart';

/*
 * App 的偏好設定，存在這台裝置：
 * 主題（預設跟隨系統）、隱藏驗證碼（同網站，所有群組共用）、允許截圖（預設不允許）、App 鎖定。
 * App 鎖定的設定存在安全儲存（見 AppLockController），這裡轉發它的變更通知。
 */
class SettingsController extends ChangeNotifier {
  SettingsController({AppLockController? appLock}) : appLock = appLock ?? AppLockController() {
    this.appLock.addListener(_onLockChanged);
  }

  static const _themeKey = 'securibit:theme';
  static const _hideKey = 'securibit:hideCodes';
  static const _screenshotKey = 'securibit:allowScreenshots';
  // 舊版只有生物辨識鎖定；現在生物辨識要搭配圖形或密碼，舊設定不再使用
  static const _legacyBiometricKey = 'securibit:biometricLock';

  final AppLockController appLock;

  ThemeMode themeMode = ThemeMode.system;
  bool hideCodes = false;
  bool allowScreenshots = false;

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
      allowScreenshots = prefs.getBool(_screenshotKey) ?? false;
      if (prefs.containsKey(_legacyBiometricKey)) await prefs.remove(_legacyBiometricKey);
    } catch (_) {
      // 讀不到就用預設值
    }
    await appLock.load();
    _applyPrivacy();
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
