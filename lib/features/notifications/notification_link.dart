import 'notification_models.dart';

/*
 * 通知的 link（網站的站內路徑）在 App 裡要打開哪裡：
 * - / → 自己的驗證碼（預設群組）
 * - /invite/<代碼> → 用邀請加入（同點邀請連結）
 * - /groups/<id> → 切到那個群組；/groups → 群組清單與邀請（側欄）
 * - /u/<id> → 使用者的個人頁面
 * - /me/update_info、/me/MyPage → 設定；/me/activity → 帳號紀錄
 * - /admin… → 後台
 * - 沒有 link → 打開收件匣
 * 其他網站有、App 沒有的頁面用瀏覽器打開網站的同一頁。不是站內路徑的一律不開。
 */
sealed class NotificationTarget {
  const NotificationTarget();
}

class InboxTarget extends NotificationTarget {
  const InboxTarget();

  @override
  bool operator ==(Object other) => other is InboxTarget;

  @override
  int get hashCode => 0;
}

/// 自己的驗證碼（預設群組）
class HomeTarget extends NotificationTarget {
  const HomeTarget();

  @override
  bool operator ==(Object other) => other is HomeTarget;

  @override
  int get hashCode => 1;
}

class InviteTarget extends NotificationTarget {
  const InviteTarget(this.code);

  final String code;

  @override
  bool operator ==(Object other) => other is InviteTarget && other.code == code;

  @override
  int get hashCode => code.hashCode;
}

class GroupTarget extends NotificationTarget {
  const GroupTarget(this.groupId);

  // null：群組清單（例如收到邀請）
  final String? groupId;

  @override
  bool operator ==(Object other) => other is GroupTarget && other.groupId == groupId;

  @override
  int get hashCode => groupId.hashCode;
}

class UserTarget extends NotificationTarget {
  const UserTarget(this.userId);

  final String userId;

  @override
  bool operator ==(Object other) => other is UserTarget && other.userId == userId;

  @override
  int get hashCode => userId.hashCode;
}

enum AppPage { settings, activity, admin }

class PageTarget extends NotificationTarget {
  const PageTarget(this.page);

  final AppPage page;

  @override
  bool operator ==(Object other) => other is PageTarget && other.page == page;

  @override
  int get hashCode => page.hashCode;
}

/// App 沒有的頁面：用瀏覽器開網站的同一頁
class WebTarget extends NotificationTarget {
  const WebTarget(this.path);

  final String path;

  @override
  bool operator ==(Object other) => other is WebTarget && other.path == path;

  @override
  int get hashCode => path.hashCode;
}

final _segment = RegExp(r'^[A-Za-z0-9_-]{1,128}$');

NotificationTarget notificationTarget(String? link) {
  final safe = safeNotificationLink(link);
  if (safe == null) return const InboxTarget();
  if (safe == '/') return const HomeTarget();
  final uri = Uri.tryParse(safe);
  if (uri == null) return const InboxTarget();
  final parts = uri.pathSegments.where((s) => s.isNotEmpty).toList();
  if (parts.isEmpty) return const InboxTarget();
  String? second() => parts.length >= 2 && _segment.hasMatch(parts[1]) ? parts[1] : null;
  switch (parts.first) {
    case 'invite':
      final code = second();
      return code == null ? const InboxTarget() : InviteTarget(code);
    case 'groups':
      return GroupTarget(second());
    case 'u':
      final id = second();
      return id == null ? const InboxTarget() : UserTarget(id);
    case 'me':
      return parts.length >= 2 && parts[1] == 'activity' ? const PageTarget(AppPage.activity) : const PageTarget(AppPage.settings);
    case 'admin':
      return const PageTarget(AppPage.admin);
    case 'notifications':
      return const InboxTarget();
  }
  return WebTarget(safe);
}
