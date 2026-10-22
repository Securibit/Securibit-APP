import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/window_visibility.dart';
import 'release.dart';
import 'update_controller.dart';
import 'update_dialog.dart';

/*
 * 自動檢查更新的時機：App 開啟後等幾秒檢查一次（登入前後都一樣，不擋啟動），之後每小時檢查一次：
 * 開著的時候每 5 分鐘看一次、回到前景時也看一次，距離上次檢查超過一小時就再查（電腦睡眠、手機在背景的時間也算）。
 * 查到新版本就在背景下載，下載並驗證好才跳出「新版本已準備好」（強烈建議更新；按「稍後」下一個小時會再提示）；
 * 這台不能自動安裝時跳出用瀏覽器下載的提示。失敗什麼都不顯示。主視窗藏著時等它再顯示才提示。
 */
class UpdateService {
  UpdateService({required this.updates, required this.navigatorKey});

  static const launchDelay = Duration(seconds: 3);
  static const recheckEvery = Duration(hours: 1);
  static const _tick = Duration(minutes: 5);

  final UpdateController updates;
  final GlobalKey<NavigatorState> navigatorKey;
  Timer? _timer;
  AppLifecycleListener? _lifecycle;
  // 主視窗藏著時查到的新版本，等視窗再顯示時提示（只留最新的一個）
  AppRelease? _pending;

  Future<void> start() async {
    if (updates.target == null) return;
    // 手動檢查（設定頁、Mac 上方選單）開始的下載好了也從這裡提示
    updates.onPrompt = _prompt;
    await updates.load();
    if (!updates.enabled) return;
    await Future<void>.delayed(launchDelay);
    await _checkAndPrompt();
    _timer = Timer.periodic(_tick, (_) => _checkIfDue());
    _lifecycle = AppLifecycleListener(onResume: _checkIfDue);
  }

  void _checkIfDue() {
    if (updates.isDue(recheckEvery)) unawaited(_checkAndPrompt());
  }

  // 要不要提示由 UpdateController 決定（onPrompt）
  Future<void> _checkAndPrompt() => updates.checkAutomatically();

  void _prompt(AppRelease release) {
    if (!WindowVisibility.visible.value) {
      if (_pending == null) WindowVisibility.visible.addListener(_onVisible);
      _pending = release;
      return;
    }
    final context = navigatorKey.currentContext;
    if (context == null) return;
    unawaited(showUpdatePrompt(context, updates, release));
  }

  void _onVisible() {
    final release = _pending;
    if (!WindowVisibility.visible.value || release == null) return;
    WindowVisibility.visible.removeListener(_onVisible);
    _pending = null;
    _prompt(release);
  }

  void dispose() {
    _timer?.cancel();
    _lifecycle?.dispose();
    WindowVisibility.visible.removeListener(_onVisible);
  }
}
