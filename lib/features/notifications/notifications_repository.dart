import '../../core/json.dart';
import '../../core/result.dart';
import '../../core/rpc.dart';
import 'notification_models.dart';

/*
 * 通知的 RPC（和網站呼叫的完全相同，見網站 database/init.sql 的 notifications_*）。
 * 只讀得到、改得到自己的通知；權限與內容都在資料庫決定。
 */

const notificationPageSize = 30;

/// category 是 null 時列出全部；before 是上一頁最後一則的 id
Future<Result<List<AppNotification>>> loadNotifications({NotificationCategory? category, int? before, int limit = notificationPageSize}) => rpc(
      'notifications_list',
      (data) => [for (final row in asMapList(data)) ?AppNotification.fromJson(row)],
      {'p_category': category?.name, 'p_before': before, 'p_limit': limit},
    );

Future<Result<UnreadCounts>> loadUnreadCounts() => rpc('notifications_unread_counts', UnreadCounts.fromJson);

/// ids 與 category 都是 null：全部標成已讀
Future<Result<void>> markNotificationsRead({List<int>? ids, NotificationCategory? category}) =>
    rpcVoid('notifications_mark_read', {'p_ids': ids, 'p_category': category?.name});

Future<Result<NotificationPrefs>> loadNotificationPrefs() => rpc('notification_prefs_get', NotificationPrefs.fromJson);

/// 只送要改的那幾種（資料庫會合併到現有設定）；回傳存好之後的設定
Future<Result<NotificationPrefs>> saveNotificationPrefs(Map<String, bool> changes) =>
    rpc('notification_prefs_set', NotificationPrefs.fromJson, {'p_overrides': changes});

/// 目前這個 session 的推播 token；null 是取消（登出前）
Future<Result<void>> registerPushToken(String? token) => rpcVoid('register_push_token', {'p_token': token});
