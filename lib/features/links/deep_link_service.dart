import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/widgets/feedback.dart';
import '../auth/auth_controller.dart';
import '../menubar/desktop_tray.dart';
import 'deep_link.dart';
import 'deep_link_controller.dart';

/*
 * 從系統接收連結（app_links；supabase_flutter 也用它接 Google 登入轉回來的連結）：
 * - App 冷啟動時帶進來的連結：getInitialLinkString（supabase 先訂閱了串流，初始連結不一定會再從串流給我們）
 * - App 已經開著時收到的連結：stringLinkStream
 * 兩邊可能給同一個連結，由 DeepLinkController 去掉重複。
 * 收到後先叫回主視窗（macOS 選單列、Linux 系統匣常駐時視窗可能藏著），等 App 鎖定判斷完才排隊，
 * 鎖著的話解鎖後才打開；格式不對的直接跳出錯誤；還沒登入時提示登入後會打開。
 * 各平台怎麼把連結交給 App：Android 的 intent-filter（https 邀請連結用 App Links）、
 * iOS / macOS 的 CFBundleURLTypes、Linux 的 .desktop MimeType（見 linux/runner/my_application.cc）、
 * Windows 安裝檔寫的登錄檔（tool/windows/securibit.iss；App 已經開著時由 windows/runner/main.cpp 交給原本的視窗）。
 */
class DeepLinkService {
  DeepLinkService({required this.links, required this.auth, required this.navigatorKey});

  final DeepLinkController links;
  final AuthController auth;
  final GlobalKey<NavigatorState> navigatorKey;

  StreamSubscription<String>? _subscription;
  bool _toldSignIn = false;

  Future<void> start() async {
    if (kIsWeb) return;
    final appLinks = AppLinks();
    _subscription = appLinks.stringLinkStream.listen((link) => unawaited(_onLink(link)), onError: (Object _) {});
    auth.addListener(_onAuthChanged);
    try {
      final initial = await appLinks.getInitialLinkString();
      if (initial != null) await _onLink(initial);
    } catch (_) {
      // 讀不到初始連結就算了（測試環境沒有原生端）
    }
  }

  Future<void> dispose() async {
    auth.removeListener(_onAuthChanged);
    await _subscription?.cancel();
  }

  Future<void> _onLink(String raw) async {
    final link = links.accept(raw);
    if (link == null) return;
    // 冷啟動時畫面可能還沒出來（錯誤對話框、提示要有畫面才顯示得出來）
    await WidgetsBinding.instance.waitUntilFirstFrameRasterized.timeout(const Duration(seconds: 5), onTimeout: () {});
    // 叫回主視窗；視窗重新顯示時 App 鎖定可能會鎖起來，等這一輪畫完再排隊
    await DesktopTray.showWindow();
    await WidgetsBinding.instance.endOfFrame.timeout(const Duration(milliseconds: 300), onTimeout: () {});

    if (link is InvalidLink) {
      final context = navigatorKey.currentContext;
      if (context != null && context.mounted) unawaited(showErrorDialog(context, link.title, link.message));
      return;
    }
    links.queue(link);
    _toldSignIn = false;
    _onAuthChanged();
  }

  // 還沒登入：提示一次登入後會打開（開 App 時還在還原 session 的話，等確定沒登入才提示）
  void _onAuthChanged() {
    if (_toldSignIn || links.pending == null || auth.status != AuthStatus.signedOut) return;
    final context = navigatorKey.currentContext;
    if (context == null || !context.mounted) return;
    _toldSignIn = true;
    showToast(context, links.pending is InviteLink ? '登入後會開啟這個邀請連結' : '登入後會開啟新增驗證碼');
  }
}
