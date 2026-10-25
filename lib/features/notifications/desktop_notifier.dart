import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

import '../../core/platform.dart';
import '../menubar/desktop_tray.dart';
import '../menubar/menu_bar_service.dart';
import 'notification_link_queue.dart';
import 'notification_models.dart';
import 'notifications_controller.dart';

/// 這幾則要怎麼跳系統通知（純邏輯，方便測試）：關掉的（skipped）、已讀的、看過的不跳；
/// 太多則（或開 App 時補上次之後的）合併成一則「你有 N 則新通知」
class DesktopAlert {
  const DesktopAlert({required this.id, required this.title, required this.body, this.link});

  final String id;
  final String title;
  final String body;
  final String? link;
}

/// after：上次跳過通知的最新一則 id；summary：一定合併成一則（開 App 時）
List<DesktopAlert> desktopAlerts(List<AppNotification> items, {int? after, bool summary = false, int maxSeparate = 3}) {
  final fresh = items.where((n) => !n.read && !n.skipped && (after == null || n.id > after)).toList();
  if (fresh.isEmpty) return const [];
  if (fresh.length == 1) {
    final n = fresh.single;
    return [DesktopAlert(id: 'n${n.id}', title: n.title, body: n.body, link: n.link)];
  }
  if (summary || fresh.length > maxSeparate) {
    return [DesktopAlert(id: 'summary', title: '你有 ${fresh.length} 則新通知', body: '打開 Securibit 查看')];
  }
  return [for (final n in fresh) DesktopAlert(id: 'n${n.id}', title: n.title, body: n.body, link: n.link)];
}

/*
 * 桌面（macOS、Linux、Windows）的系統通知：App 開著或常駐在選單列／系統匣時，
 * 收到 sync_signals 的 notifications 後 NotificationsController 讀到新的通知，在這裡跳系統通知；
 * 使用者在通知分頁關掉的那一類（push_state 是 skipped）不跳，鈴鐺裡一樣看得到。
 * 開 App 時把上次之後的未讀合併成一則「你有 N 則新通知」。點了系統通知叫回主視窗並打開對應的畫面。
 * 原生端：macOS 是 UNUserNotificationCenter（MenuBarController.swift），Linux 是 GNotification（tray.cc），
 * Windows 是系統匣圖示的通知（tray.cpp 的 Shell_NotifyIcon NIF_INFO），都不多帶套件。
 * 「上次跳到哪一則」記在這台裝置（每個帳號各一個），重開 App 不會重複跳。
 */
class DesktopNotifier {
  DesktopNotifier._();

  static const _key = 'securibit:notifiedUpTo:';
  static bool _asked = false;

  static void start(NotificationsController notifications, NotificationLinkQueue links) {
    if (!AppPlatform.isDesktop) return;
    MenuBarService.onNotificationClicked = links.push;
    notifications.onFirst = (uid, items) => unawaited(_onFirst(uid, items));
    notifications.onNew = (items) {
      final uid = notifications.uid;
      if (uid != null) unawaited(_show(uid, desktopAlerts(items), items));
    };
  }

  static Future<void> _onFirst(String uid, List<AppNotification> items) async {
    final prefs = await _prefs();
    final after = prefs?.getInt('$_key$uid');
    await _show(uid, desktopAlerts(items, after: after, summary: true), items);
  }

  static Future<void> _show(String uid, List<DesktopAlert> alerts, List<AppNotification> items) async {
    // 記下看過的最新一則，下次開 App 不會再跳
    if (items.isNotEmpty) {
      final max = items.map((n) => n.id).reduce((a, b) => a > b ? a : b);
      final prefs = await _prefs();
      final before = prefs?.getInt('$_key$uid');
      if (before == null || max > before) await prefs?.setInt('$_key$uid', max);
    }
    if (alerts.isEmpty) return;
    if (!_asked) {
      _asked = true;
      await DesktopTray.requestNotifyPermission();
    }
    for (final alert in alerts) {
      await DesktopTray.notify(id: alert.id, title: alert.title, body: alert.body, link: alert.link);
    }
  }

  static Future<SharedPreferences?> _prefs() async {
    try {
      return await SharedPreferences.getInstance();
    } catch (_) {
      return null;
    }
  }
}
