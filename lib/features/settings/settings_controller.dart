import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/*
 * App 的偏好設定，存在這台裝置：
 * 主題（預設跟隨系統）、隱藏驗證碼（同網站，所有群組共用）、生物辨識鎖定。
 */
class SettingsController extends ChangeNotifier {
  static const _themeKey = 'securibit:theme';
  static const _hideKey = 'securibit:hideCodes';
  static const _biometricKey = 'securibit:biometricLock';

  ThemeMode themeMode = ThemeMode.system;
  bool hideCodes = false;
  bool biometricLock = false;

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
      biometricLock = prefs.getBool(_biometricKey) ?? false;
    } catch (_) {
      // 讀不到就用預設值
    }
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

  void setBiometricLock(bool enabled) {
    biometricLock = enabled;
    notifyListeners();
    _prefs?.setBool(_biometricKey, enabled);
  }
}
