import '../../core/json.dart';

/*
 * 通知的分類與事件（同網站 database/init.sql 的 notification_defaults() 與網站的通知分頁）。
 * 標題與內文由資料庫產生，App 直接顯示，不自己組字；這裡只有分類、開關的名稱與預設值。
 * 新增事件時：資料庫的事件表與預設、網站與 App 的通知分頁一起改（見網站 docs/security-rules.md）。
 */
enum NotificationCategory {
  system('系統'),
  account('帳戶'),
  feature('功能');

  const NotificationCategory(this.label);

  final String label;

  static NotificationCategory? tryParse(Object? value) {
    for (final c in values) {
      if (c.name == value) return c;
    }
    return null;
  }
}

/// 一種通知：type 是資料庫的名稱；locked 是不能關（重要公告）
class NotificationTypeDef {
  const NotificationTypeDef({
    required this.type,
    required this.category,
    required this.label,
    required this.description,
    this.defaultOn = true,
    this.locked = false,
  });

  final String type;
  final NotificationCategory category;
  final String label;
  final String description;
  final bool defaultOn;
  final bool locked;
}

// 順序同資料庫的 notification_prefs_get()；名稱與說明同網站 src/lib/notifications/types.ts
const notificationTypes = <NotificationTypeDef>[
  NotificationTypeDef(type: 'announce_important', category: NotificationCategory.system, label: '重要公告', description: '影響帳戶安全或服務使用的重大事項，無法關閉', locked: true),
  NotificationTypeDef(type: 'announce_update', category: NotificationCategory.system, label: '更新公告', description: '新版本與新功能'),
  NotificationTypeDef(type: 'announce_promo', category: NotificationCategory.system, label: '推廣', description: '活動與推廣訊息'),
  NotificationTypeDef(type: 'announce_other', category: NotificationCategory.system, label: '其他公告', description: '其他服務公告'),
  NotificationTypeDef(type: 'new_login', category: NotificationCategory.account, label: '新的登入', description: '你的帳戶在新的裝置登入時'),
  NotificationTypeDef(type: 'vault_changed', category: NotificationCategory.account, label: '金鑰加密密碼變更', description: '設定、變更或關閉金鑰加密的密碼時'),
  NotificationTypeDef(type: 'admin_changed_role', category: NotificationCategory.account, label: '管理員變更了我的網站身分組', description: '管理員在後台變更你的網站身分組時'),
  NotificationTypeDef(type: 'admin_changed_username', category: NotificationCategory.account, label: '管理員修改了我的 @ID', description: '管理員在後台修改或清除你的 @ID 時'),
  NotificationTypeDef(type: 'admin_changed_codes', category: NotificationCategory.account, label: '管理員修改了我的驗證碼', description: '管理員在後台修改或刪除你的驗證碼時'),
  NotificationTypeDef(type: 'group_invite', category: NotificationCategory.feature, label: '群組邀請', description: '有人用 Email 或 @ID 邀請你加入群組'),
  NotificationTypeDef(type: 'invite_answered', category: NotificationCategory.feature, label: '邀請被接受或拒絕', description: '你邀請的人接受或拒絕，或有人用你的邀請連結加入'),
  NotificationTypeDef(type: 'member_added', category: NotificationCategory.feature, label: '被加入群組', description: '有人直接把你加入群組'),
  NotificationTypeDef(type: 'member_removed', category: NotificationCategory.feature, label: '被移出群組', description: '你被移出群組時'),
  NotificationTypeDef(type: 'member_banned', category: NotificationCategory.feature, label: '被群組封鎖', description: '你被群組封鎖時'),
  NotificationTypeDef(type: 'group_roles_changed', category: NotificationCategory.feature, label: '群組身分組變更', description: '你在群組裡的身分組被變更或刪除時'),
  NotificationTypeDef(type: 'ownership_received', category: NotificationCategory.feature, label: '成為群組擁有者', description: '有人把群組轉移給你'),
  NotificationTypeDef(type: 'group_deleted', category: NotificationCategory.feature, label: '群組被刪除', description: '你所在的群組被刪除時'),
  NotificationTypeDef(type: 'group_encryption_changed', category: NotificationCategory.feature, label: '群組加密變更', description: '你所在的群組開啟或關閉加密時'),
  NotificationTypeDef(type: 'codes_changed', category: NotificationCategory.feature, label: '群組驗證碼有變動', description: '其他成員新增、修改或刪除你看得到的驗證碼時；短時間內的多筆變更合成一則', defaultOn: false),
];

NotificationTypeDef? notificationTypeDef(String type) {
  for (final def in notificationTypes) {
    if (def.type == type) return def;
  }
  return null;
}

/// 一則通知（notifications_list 的一列）
class AppNotification {
  const AppNotification({
    required this.id,
    required this.category,
    required this.type,
    required this.title,
    required this.body,
    required this.link,
    required this.createdAt,
    this.readAt,
    this.pushState = 'pending',
  });

  final int id;
  final NotificationCategory category;
  final String type;
  final String title;
  final String body;
  // 站內路徑（/ 開頭），沒有是 null
  final String? link;
  final DateTime createdAt;
  final DateTime? readAt;
  // pending／sending／sent／skipped（skipped：使用者關掉了這種通知，不跳系統通知）
  final String pushState;

  bool get read => readAt != null;

  bool get skipped => pushState == 'skipped';

  AppNotification markRead(DateTime at) => AppNotification(
        id: id,
        category: category,
        type: type,
        title: title,
        body: body,
        link: link,
        createdAt: createdAt,
        readAt: readAt ?? at,
        pushState: pushState,
      );

  static AppNotification? fromJson(Map<String, dynamic> json) {
    final id = asInt(json['id'], -1);
    final created = DateTime.tryParse(asString(json['created_at']));
    if (id < 0 || created == null) return null;
    final type = asString(json['type']);
    final category = NotificationCategory.tryParse(json['category']) ?? notificationTypeDef(type)?.category ?? NotificationCategory.system;
    return AppNotification(
      id: id,
      category: category,
      type: type,
      title: asString(json['title']),
      body: asString(json['body']),
      link: safeNotificationLink(json['link']),
      createdAt: created.toLocal(),
      readAt: DateTime.tryParse(asString(json['read_at']))?.toLocal(),
      pushState: asString(json['push_state'], 'pending'),
    );
  }
}

/// 只接受站內路徑（同網站的 safeNotificationLink、資料庫的規則）：/ 開頭，不含 //、\、空白與控制字元
String? safeNotificationLink(Object? value) {
  if (value is! String || value.isEmpty || value.length > 500) return null;
  if (!value.startsWith('/') || value.contains('//') || value.contains('\\')) return null;
  if (value.runes.any((c) => c < 0x20 || c == 0x7f || String.fromCharCode(c).trim().isEmpty)) return null;
  return value;
}

/// 未讀數（notifications_unread_counts）
class UnreadCounts {
  const UnreadCounts({this.total = 0, this.system = 0, this.account = 0, this.feature = 0});

  static const zero = UnreadCounts();

  final int total;
  final int system;
  final int account;
  final int feature;

  int of(NotificationCategory? category) => switch (category) {
        null => total,
        NotificationCategory.system => system,
        NotificationCategory.account => account,
        NotificationCategory.feature => feature,
      };

  /// 格式：{ total, system, account, feature }（也接受一列的陣列）
  static UnreadCounts fromJson(Object? data) {
    final map = data is List ? (data.isEmpty ? <String, dynamic>{} : asMap(data.first)) : asMap(data);
    final system = asInt(map['system']);
    final account = asInt(map['account']);
    final feature = asInt(map['feature']);
    return UnreadCounts(
      total: map.containsKey('total') ? asInt(map['total']) : system + account + feature,
      system: system,
      account: account,
      feature: feature,
    );
  }

  /// 這幾則標成已讀後的數字（已經讀過的不算）
  UnreadCounts minus(Iterable<AppNotification> items) {
    var s = 0, a = 0, f = 0;
    for (final item in items) {
      if (item.read) continue;
      switch (item.category) {
        case NotificationCategory.system:
          s++;
        case NotificationCategory.account:
          a++;
        case NotificationCategory.feature:
          f++;
      }
    }
    int sub(int value, int by) => value - by < 0 ? 0 : value - by;
    return UnreadCounts(total: sub(total, s + a + f), system: sub(system, s), account: sub(account, a), feature: sub(feature, f));
  }

  @override
  bool operator ==(Object other) =>
      other is UnreadCounts && other.total == total && other.system == system && other.account == account && other.feature == feature;

  @override
  int get hashCode => Object.hash(total, system, account, feature);
}

/*
 * 通知開關（notification_prefs）：資料庫只存和預設不同的（overrides），這裡算出每一種實際開或關。
 * 重要公告一律開著，不能關；不認得的 type 忽略。
 * 存的時候只送改了的那一種（notification_prefs_set 會合併到現有設定）。
 */
class NotificationPrefs {
  const NotificationPrefs([this.overrides = const {}]);

  final Map<String, bool> overrides;

  bool enabled(String type) {
    final def = notificationTypeDef(type);
    if (def == null) return true;
    if (def.locked) return true;
    return overrides[type] ?? def.defaultOn;
  }

  /// 改一種：和預設相同就不留在 overrides；不能關的、不認得的不動
  NotificationPrefs set(String type, bool on) {
    final def = notificationTypeDef(type);
    if (def == null || def.locked) return this;
    final next = Map<String, bool>.from(overrides);
    if (on == def.defaultOn) {
      next.remove(type);
    } else {
      next[type] = on;
    }
    return NotificationPrefs(next);
  }

  /// notification_prefs_get／set 的回傳：[{ type, category, enabled, default, locked }]，依實際的開關算出 overrides。
  /// 也接受 { type: bool } 的格式
  static NotificationPrefs fromJson(Object? data) {
    final values = <String, Object?>{};
    if (data is List) {
      for (final row in asMapList(data)) {
        values[asString(row['type'])] = row['enabled'];
      }
    } else {
      values.addAll(asMap(data));
    }
    final overrides = <String, bool>{};
    for (final e in values.entries) {
      final def = notificationTypeDef(e.key);
      final value = e.value;
      if (def == null || def.locked || value is! bool) continue;
      if (value != def.defaultOn) overrides[e.key] = value;
    }
    return NotificationPrefs(overrides);
  }
}
