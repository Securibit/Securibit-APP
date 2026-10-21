import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/window_visibility.dart';
import '../menubar/desktop_tray.dart';
import 'release.dart';
import 'update_controller.dart';
import 'update_dialog.dart';

/*
 * 自動檢查更新的時機：App 開啟後等幾秒檢查一次（登入前後都一樣，不擋啟動）；
 * 桌面版常駐在選單列／系統匣，可能好幾天都不會重開，所以每小時看一次，距離上次檢查超過一天就再查。
 * 查到新版本才跳出提示；失敗什麼都不顯示。主視窗藏著時等它再顯示才提示。
 */
class UpdateService {
  UpdateService({required this.updates, required this.navigatorKey});

  static const launchDelay = Duration(seconds: 3);
  static const recheckEvery = Duration(days: 1);
  static const _tick = Duration(hours: 1);

  final UpdateController updates;
  final GlobalKey<NavigatorState> navigatorKey;
  Timer? _timer;
  // 主視窗藏著時查到的新版本，等視窗再顯示時提示（只留最新的一個）
  AppRelease? _pending;

  Future<void> start() async {
    if (!updates.supported) return;
    await updates.load();
    if (!updates.enabled) return;
    await Future<void>.delayed(launchDelay);
    await _checkAndPrompt();
    if (DesktopTray.supported) {
      _timer = Timer.periodic(_tick, (_) {
        if (updates.isDue(recheckEvery)) unawaited(_checkAndPrompt());
      });
    }
  }

  Future<void> _checkAndPrompt() async {
    final release = await updates.checkAutomatically();
    if (release != null) _prompt(release);
  }

  void _prompt(AppRelease release) {
    if (!WindowVisibility.visible.value) {
      if (_pending == null) WindowVisibility.visible.addListener(_onVisible);
      _pending = release;
      return;
    }
    final context = navigatorKey.currentContext;
    if (context == null) return;
    unawaited(showUpdateDialog(context, updates, release));
  }

  void _onVisible() {
    final release = _pending;
    if (!WindowVisibility.visible.value || release == null) return;
    WindowVisibility.visible.removeListener(_onVisible);
    _pending = null;
    // 這段時間裡可能已經在設定頁略過這一版
    if (updates.shouldPrompt(release)) _prompt(release);
  }

  void dispose() {
    _timer?.cancel();
    WindowVisibility.visible.removeListener(_onVisible);
  }
}
