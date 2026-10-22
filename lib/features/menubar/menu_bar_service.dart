import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/window_visibility.dart';
import '../auth/auth_controller.dart';
import '../groups/groups_controller.dart';
import '../settings/settings_controller.dart';
import '../settings/settings_view.dart';
import '../update/update_controller.dart';
import '../update/update_dialog.dart';
import '../vault/vault_controller.dart';
import 'desktop_tray.dart';
import 'menu_bar_codes.dart';
import 'menu_bar_model.dart';

/*
 * 桌面常駐選單（macOS 選單列、Linux 與 Windows 系統匣）的 Dart 端：Dart 是唯一的資料來源，原生端只負責畫選單。
 * - 選單關著：資料有變時只送結構（群組、名稱，驗證碼是佔位文字），打開時馬上就有東西可畫
 * - 選單打開（menuWillOpen）與開著的每一秒（tick，計時器在原生端；Windows 選單開著時不更新）：回傳含驗證碼的完整內容
 * - Linux 不一定知道選單什麼時候打開，主視窗藏起來時也當作開著，每秒送完整內容（見 DesktopTray.refreshWhileHidden）
 * - 點了某一筆（copy）：在這裡（由 Rust）算當下的碼並複製，原生端與 Dart 都不會拿到金鑰
 * - 主視窗藏起來或重新顯示時通知 App 鎖定（見 WindowVisibility）
 */
class MenuBarService {
  MenuBarService({
    required this.settings,
    required this.auth,
    required this.groups,
    required this.vault,
    required this.codes,
    required this.navigatorKey,
  });

  final SettingsController settings;
  final AuthController auth;
  final GroupsController groups;
  final VaultController vault;
  final MenuBarCodes codes;
  final GlobalKey<NavigatorState> navigatorKey;

  bool? _enabled;
  bool _open = false;
  bool _pushScheduled = false;
  String? _lastPushed;

  void start() {
    if (!DesktopTray.supported) return;
    DesktopTray.channel.setMethodCallHandler(_handle);
    for (final source in <Listenable>[settings, auth, groups, vault, codes]) {
      source.addListener(_onChanged);
    }
    // 網站或其他裝置改了驗證碼（即時通知；輪詢的檢查不算，避免每分鐘多記一筆「查看金鑰」）
    groups.codesSignals.where((s) => s.confirmed).listen((s) => codes.markStale(s.groupId));
    _onChanged();
  }

  bool get _active => settings.showInMenuBar;

  // 要不要送含驗證碼的完整內容：選單開著，或 Linux 主視窗藏著（只能從系統匣看驗證碼）
  bool get _live => _open || (DesktopTray.refreshWhileHidden && !WindowVisibility.visible.value);

  void _onChanged() {
    final enabled = _active;
    if (enabled != _enabled) {
      _enabled = enabled;
      _lastPushed = null;
      if (!enabled) codes.reset(null);
      unawaited(DesktopTray.setEnabled(enabled));
    }
    // 登出後不留任何群組的資料
    if (auth.profile == null) codes.reset(null);
    // 不在選單列顯示驗證碼時也不留各群組的資料
    if (!settings.showCodesInMenuBar) codes.reset(null);
    if (!enabled || _pushScheduled) return;
    // 同一輪的多個變更合成一次
    _pushScheduled = true;
    scheduleMicrotask(() {
      _pushScheduled = false;
      if (!_active) return;
      _refreshCodes(network: _live);
      unawaited(_push(_model(withCodes: _live)));
    });
  }

  // 只在選單開著時才連網；關著時只從離線快取補上
  void _refreshCodes({required bool network}) {
    final uid = auth.profile?.uid;
    final list = groups.groups;
    if (uid == null || list == null || !settings.showCodesInMenuBar) return;
    codes.refresh(uid: uid, groups: list, vaultKeyId: vault.keyId, network: network);
  }

  MenuBarModel _model({required bool withCodes}) => buildMenuBarModel(
        signedIn: auth.status == AuthStatus.signedIn,
        showCodes: settings.showCodesInMenuBar,
        profileReady: auth.profile != null,
        appLocked: settings.appLock.lockedAt(DateTime.now()),
        hideCodes: settings.hideCodes,
        vaultUnlocked: vault.status == VaultStatus.unlocked && vault.keyId != null,
        groups: groups.groups,
        groupsError: groups.error,
        data: codes.data,
        nowMs: DateTime.now().millisecondsSinceEpoch,
        withCodes: withCodes,
      );

  // 內容沒變就不送
  Future<void> _push(MenuBarModel model) async {
    final map = model.toMap();
    final encoded = jsonEncode(map);
    if (encoded == _lastPushed) return;
    _lastPushed = encoded;
    await DesktopTray.update(map);
  }

  Map<String, Object?> _snapshot() {
    _refreshCodes(network: true);
    final map = _model(withCodes: true).toMap();
    _lastPushed = jsonEncode(map);
    return map;
  }

  Future<Object?> _handle(MethodCall call) async {
    switch (call.method) {
      case 'menuWillOpen':
        _open = true;
        return _snapshot();
      case 'tick':
        return _live ? _snapshot() : null;
      case 'menuDidClose':
        _open = false;
        // 關起來後原生端只留結構，不留驗證碼（Linux 視窗藏著時繼續送完整內容）
        if (!_live) unawaited(_push(_model(withCodes: false)));
        return null;
      case 'copy':
        final id = (call.arguments as Map?)?['id'];
        if (id is! String) return false;
        final code = _model(withCodes: true).codeFor(id, DateTime.now().millisecondsSinceEpoch);
        if (code == null) return false;
        await Clipboard.setData(ClipboardData(text: code));
        return true;
      case 'openSettings':
        _openSettings();
        return null;
      case 'checkForUpdates':
        _checkForUpdates();
        return null;
      case 'windowWillHide':
        WindowVisibility.visible.value = false;
        // 等鎖定畫面畫好再藏視窗，下次顯示時不會先閃過驗證碼
        await WidgetsBinding.instance.endOfFrame.timeout(const Duration(milliseconds: 300), onTimeout: () {});
        return null;
      case 'windowDidShow':
        WindowVisibility.visible.value = true;
        if (!_live) unawaited(_push(_model(withCodes: false)));
        return null;
    }
    throw MissingPluginException();
  }

  // Mac 上方選單的「檢查更新…」：原生端已經把視窗叫出來
  void _checkForUpdates() {
    final context = navigatorKey.currentContext;
    if (context == null) return;
    unawaited(checkForUpdatesNow(context, context.read<UpdateController>()));
  }

  // 「設定…」：原生端已經把視窗叫出來，這裡打開設定（已經開著就不再開一個）
  void _openSettings() {
    final context = navigatorKey.currentContext;
    if (context == null || auth.profile == null) return;
    unawaited(openSettings(context));
  }
}
