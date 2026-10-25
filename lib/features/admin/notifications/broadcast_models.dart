import '../../../core/json.dart';
import '../admin_models.dart';

/*
 * 後台「發送通知」與「通知設定」的資料（同網站 src/lib/notifications/types.ts、broadcast.ts）。
 * 權限都在 RPC 檢查：發送、預覽、發送紀錄要「發送通知」，讀設定要「進入後台」，改設定要「管理使用者」。
 */

/// 標題、內文、連結、最低版本說明的長度上限（和資料庫一致）
const broadcastTitleMax = 100;
const broadcastBodyMax = 500;
const broadcastLinkMax = 500;
const minVersionMessageMax = 500;

/// 一次最多的人數（資料庫也會擋）
const broadcastUserLimit = 10000;

/// 一次最多指定的使用者（更多的話用身分組或所有使用者）
const broadcastUserPickMax = 200;

enum BroadcastKind {
  important('重要公告', '影響帳戶安全或服務使用的重大事項。使用者無法關閉，一律推播'),
  update('更新公告', '新版本與新功能'),
  promo('推廣', '活動與推廣訊息'),
  other('其他公告', '其他服務公告');

  const BroadcastKind(this.label, this.description);

  final String label;
  final String description;

  static String nameOf(String key) => values.where((k) => k.name == key).firstOrNull?.label ?? key;
}

/// 平台條件（ios、android、macos、windows、linux、web）
const broadcastPlatforms = <(String, String)>[
  ('ios', 'iOS'),
  ('android', 'Android'),
  ('macos', 'macOS'),
  ('windows', 'Windows'),
  ('linux', 'Linux'),
  ('web', '只用網站'),
];

String broadcastPlatformName(String key) => broadcastPlatforms.where((p) => p.$1 == key).firstOrNull?.$2 ?? key;

final _semver = RegExp(r'^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(-[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?(\+[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?$');

/// 版本號（semver）：1.5.0、1.5.0-beta.1；+build 也接受（同網站 isValidVersion）
bool isValidVersion(String value) => _semver.hasMatch(value.trim());

/// 對象條件（admin_broadcast_preview／send 的 p_filter）：全部可選，同時符合才算
class BroadcastFilter {
  const BroadcastFilter({
    this.allUsers = false,
    this.userIds = const [],
    this.siteRoleIds = const [],
    this.platforms = const [],
    this.sessionIds = const [],
    this.versionMin,
    this.versionMax,
    this.lastSeenDays,
  });

  final bool allUsers;
  final List<String> userIds;
  final List<String> siteRoleIds;
  final List<String> platforms;
  final List<String> sessionIds;
  final String? versionMin;
  final String? versionMax;
  final int? lastSeenDays;

  /// 只放有設定的條件（空陣列等於沒給）；「所有使用者」打開時不送指定的使用者、身分組與裝置
  Map<String, dynamic> toJson() => {
        if (allUsers) 'all_users': true,
        if (!allUsers && userIds.isNotEmpty) 'user_ids': userIds,
        if (!allUsers && siteRoleIds.isNotEmpty) 'site_role_ids': siteRoleIds,
        if (platforms.isNotEmpty) 'platforms': platforms,
        if (!allUsers && userIds.isNotEmpty && sessionIds.isNotEmpty) 'session_ids': sessionIds,
        if (versionMin != null && versionMin!.trim().isNotEmpty) 'version_min': versionMin!.trim(),
        if (versionMax != null && versionMax!.trim().isNotEmpty) 'version_max': versionMax!.trim(),
        if (lastSeenDays != null && lastSeenDays! > 0) 'last_seen_days': lastSeenDays,
      };

  bool get hasTarget => toJson().isNotEmpty;

  static List<String> _strings(Object? value) => value is List ? value.whereType<String>().toList() : const [];

  static BroadcastFilter fromJson(Object? json) {
    final map = asMap(json);
    return BroadcastFilter(
      allUsers: asBool(map['all_users']),
      userIds: _strings(map['user_ids']),
      siteRoleIds: _strings(map['site_role_ids']),
      platforms: _strings(map['platforms']),
      sessionIds: _strings(map['session_ids']),
      versionMin: asNullableString(map['version_min']),
      versionMax: asNullableString(map['version_max']),
      lastSeenDays: map['last_seen_days'] == null ? null : asInt(map['last_seen_days']),
    );
  }

  /// 發送紀錄裡的簡短說明（同網站 BroadcastHistory 的 filterText）；roleNames：身分組 id → 名稱
  String describe(Map<String, String> roleNames) => [
        if (allUsers) '所有使用者',
        if (userIds.isNotEmpty) '${userIds.length} 位指定的使用者',
        if (siteRoleIds.isNotEmpty) '身分組 ${siteRoleIds.map((id) => roleNames[id] ?? '已刪除的身分組').join('、')}',
        if (platforms.isNotEmpty) platforms.map(broadcastPlatformName).join('、'),
        if (sessionIds.isNotEmpty) '${sessionIds.length} 台指定的裝置',
        if (versionMin != null || versionMax != null) '版本 ${versionMin ?? '不限'} ～ ${versionMax ?? '不限'}',
        if (lastSeenDays != null && lastSeenDays! > 0) '最近 $lastSeenDays 天用過',
      ].join(' · ');
}

/// admin_broadcast_preview：使用者數、App 裝置數、收得到推播的裝置數
class BroadcastPreview {
  const BroadcastPreview({required this.users, required this.devices, required this.pushDevices, this.limit = broadcastUserLimit});

  final int users;
  final int devices;
  final int pushDevices;
  final int limit;

  bool get tooMany => users > limit;

  static BroadcastPreview fromJson(Object? json) {
    final map = asMap(json);
    return BroadcastPreview(
      users: asInt(map['users']),
      devices: asInt(map['devices']),
      pushDevices: asInt(map['push_devices']),
      limit: map['limit'] == null ? broadcastUserLimit : asInt(map['limit'], broadcastUserLimit),
    );
  }
}

/// admin_broadcasts_list 的一筆
class BroadcastRecord {
  const BroadcastRecord({
    required this.id,
    required this.kind,
    required this.title,
    required this.body,
    required this.link,
    required this.filter,
    required this.createdBy,
    required this.createdAt,
    required this.userCount,
    required this.deviceCount,
  });

  final int id;
  final String kind;
  final String title;
  final String body;
  final String? link;
  final BroadcastFilter filter;
  final PersonBrief? createdBy;
  final String? createdAt;
  final int userCount;
  final int deviceCount;

  static BroadcastRecord fromJson(Map<String, dynamic> json) => BroadcastRecord(
        id: asInt(json['id']),
        kind: asString(json['kind']),
        title: asString(json['title']),
        body: asString(json['body']),
        link: asNullableString(json['link']),
        filter: BroadcastFilter.fromJson(json['filter']),
        createdBy: PersonBrief.fromJson(json['created_by']),
        createdAt: asNullableString(json['created_at']),
        userCount: asInt(json['user_count']),
        deviceCount: asInt(json['device_count']),
      );
}

/// 後台修改帳號時要不要通知本人（site_settings 的 notify_admin_changes）
class AdminChangeNotify {
  const AdminChangeNotify({this.role = true, this.username = true, this.codes = true});

  final bool role;
  final bool username;
  final bool codes;

  bool of(String key) => switch (key) {
        'role' => role,
        'username' => username,
        _ => codes,
      };

  AdminChangeNotify copyWith(String key, bool on) => AdminChangeNotify(
        role: key == 'role' ? on : role,
        username: key == 'username' ? on : username,
        codes: key == 'codes' ? on : codes,
      );

  Map<String, bool> toJson() => {'role': role, 'username': username, 'codes': codes};

  // 沒有的欄位當作開著（預設）
  static AdminChangeNotify fromJson(Object? json) {
    final map = asMap(json);
    bool read(String key) => map[key] is bool ? map[key] as bool : true;
    return AdminChangeNotify(role: read('role'), username: read('username'), codes: read('codes'));
  }
}

/// 後台通知設定的三種開關（同網站 SettingsClient 的 ADMIN_CHANGE_ROWS）
const adminChangeRows = <(String, String, String)>[
  ('role', '變更網站身分組', '在後台指派或移除使用者的網站身分組'),
  ('username', '修改 @ID', '在後台修改或清除使用者的 @ID'),
  ('codes', '修改驗證碼', '在後台修改或刪除使用者的驗證碼'),
];

/// 最低 App 版本（null 是沒有設定）
class MinAppVersion {
  const MinAppVersion({required this.version, required this.message});

  final String version;
  final String message;

  Map<String, String> toJson() => {'version': version, 'message': message};

  static MinAppVersion? fromJson(Object? json) {
    if (json is! Map) return null;
    final version = json['version'];
    if (version is! String || version.isEmpty) return null;
    return MinAppVersion(version: version, message: asString(json['message']));
  }
}

/// admin_site_settings_get
class SiteSettings {
  const SiteSettings({required this.notifyAdminChanges, required this.minAppVersion});

  final AdminChangeNotify notifyAdminChanges;
  final MinAppVersion? minAppVersion;

  static SiteSettings fromJson(Object? json) {
    final map = asMap(json);
    return SiteSettings(
      notifyAdminChanges: AdminChangeNotify.fromJson(map['notify_admin_changes']),
      minAppVersion: MinAppVersion.fromJson(map['min_app_version']),
    );
  }
}
