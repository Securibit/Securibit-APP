import '../../core/json.dart';
import '../codes/totp/categories.dart';
import '../codes/totp/totp_params.dart';

/*
 * 後台用到的 RPC 回傳格式，欄位對應網站的 TS 型別：
 * src/types/Permission/Permission.ts、src/types/Admin/Admin.ts、src/types/Activity/Activity.ts、
 * src/types/Group/Group.ts，以及 migration 裡各個函式的 jsonb_build_object。
 */

/// 身分組（全站與群組共用；site_roles_list()、group_detail().roles）
class Role {
  const Role({
    required this.id,
    required this.name,
    required this.color,
    required this.position,
    required this.permissions,
    required this.isDefault,
    required this.memberCount,
  });

  final String id;
  final String name;
  // '#rrggbb' 或空字串（無顏色）
  final String color;
  // 越大越高；@everyone 是 0
  final int position;
  final int permissions;
  // @everyone
  final bool isDefault;
  final int memberCount;

  factory Role.fromJson(Map<String, dynamic> json) => Role(
        id: asString(json['id']),
        name: asString(json['name']),
        color: asString(json['color']),
        position: asInt(json['position']),
        permissions: asInt(json['permissions']),
        isDefault: asBool(json['is_default']),
        memberCount: asInt(json['member_count']),
      );

  RoleInput get input => RoleInput(name: name, color: color, permissions: permissions);
}

/// 身分組的簡短資料（me_permissions().roles：沒有權限與人數）
class RoleBrief {
  const RoleBrief({required this.id, required this.name, required this.color, required this.position});

  final String id;
  final String name;
  final String color;
  final int position;

  factory RoleBrief.fromJson(Map<String, dynamic> json) => RoleBrief(
        id: asString(json['id']),
        name: asString(json['name']),
        color: asString(json['color']),
        position: asInt(json['position']),
      );
}

/// 編輯身分組時送出的內容
class RoleInput {
  const RoleInput({required this.name, required this.color, required this.permissions});

  final String name;
  final String color;
  final int permissions;

  RoleInput copyWith({String? name, String? color, int? permissions}) =>
      RoleInput(name: name ?? this.name, color: color ?? this.color, permissions: permissions ?? this.permissions);

  // 名稱完全相同、顏色不分大小寫、權限相同
  bool sameAs(RoleInput other) =>
      name == other.name && color.toLowerCase() == other.color.toLowerCase() && permissions == other.permissions;
}

/// me_permissions()：自己的全站權限（已展開，管理員是全部）
class SiteAccess {
  const SiteAccess({required this.permissions, required this.topPosition, required this.roles, this.isOwner = false});

  static const none = SiteAccess(permissions: 0, topPosition: 0, roles: []);

  final int permissions;
  final int topPosition;
  // 我是全站擁有者（唯一不受全站階層限制的人）
  final bool isOwner;
  // 不含 @everyone，由高到低
  final List<RoleBrief> roles;

  static SiteAccess fromJson(Object? json) {
    if (json is! Map) return none;
    final map = asMap(json);
    return SiteAccess(
      permissions: asInt(map['permissions']),
      topPosition: asInt(map['top_position']),
      roles: asMapList(map['roles']).map(RoleBrief.fromJson).toList(),
      isOwner: asBool(map['is_owner']),
    );
  }
}

/// 使用者的基本資料（user_brief()：成員、紀錄的操作者、群組擁有者）；email 只有有權限時才有
class PersonBrief {
  const PersonBrief({required this.id, required this.name, this.username, this.photoUrl, this.email});

  final String id;
  final String name;
  final String? username;
  final String? photoUrl;
  final String? email;

  static PersonBrief? fromJson(Object? json) {
    if (json is! Map) return null;
    final map = asMap(json);
    return PersonBrief(
      id: asString(map['id']),
      name: asString(map['name']),
      username: asNullableString(map['username']),
      photoUrl: asNullableString(map['photo_url']),
      email: asNullableString(map['email']),
    );
  }

  // 稱呼：名稱 → @ID → email
  String get displayName => name.isNotEmpty ? name : (username != null ? '@$username' : (email ?? '這位使用者'));

  // 名稱下面的灰字：@ID，沒有時用 email
  String? get subtitle => username != null ? '@$username' : email;
}

/// admin_users() / admin_user() 的使用者（admin_user_json）
class AdminUser {
  const AdminUser({
    required this.id,
    required this.email,
    required this.name,
    required this.username,
    required this.photoUrl,
    required this.creationTime,
    required this.lastLoginAt,
    required this.lastLoginIp,
    required this.lastLoginDevice,
    this.lastActiveAt,
    required this.roleIds,
    required this.topPosition,
    required this.totpCount,
    required this.vaultEnabled,
    this.isOwner,
  });

  final String id;
  final String email;
  final String name;
  final String? username;
  final String? photoUrl;
  final String? creationTime;
  final String? lastLoginAt;
  // 階層不比對方高時資料庫不給（null）
  final String? lastLoginIp;
  final String? lastLoginDevice;
  // 最後活動：所有登入中裝置的最後活動取最新的；沒有登入中的裝置（或舊的資料庫）是 null
  final String? lastActiveAt;
  final List<String> roleIds;
  final int topPosition;
  // 預設群組的驗證碼數
  final int totpCount;
  final bool vaultEnabled;
  // 全站擁有者（只有擁有者自己能管理）；舊的資料庫沒有這個欄位時是 null
  final bool? isOwner;

  factory AdminUser.fromJson(Map<String, dynamic> json) => AdminUser(
        id: asString(json['id']),
        email: asString(json['email']),
        name: asString(json['name']),
        username: asNullableString(json['username']),
        photoUrl: asNullableString(json['photo_url']),
        creationTime: asNullableString(json['creation_time']),
        lastLoginAt: asNullableString(json['last_login_at']),
        // 空字串（沒有紀錄）和 null（不公開）要分開
        lastLoginIp: json['last_login_ip'] is String ? json['last_login_ip'] as String : null,
        lastLoginDevice: asNullableString(json['last_login_device']),
        lastActiveAt: asNullableString(json['last_active_at']),
        roleIds: _stringList(json['role_ids']),
        topPosition: asInt(json['top_position']),
        totpCount: asInt(json['totp_count']),
        vaultEnabled: asBool(json['vault_enabled']),
        isOwner: json['is_owner'] is bool ? json['is_owner'] as bool : null,
      );

  String get displayName => name.isNotEmpty ? name : (email.isNotEmpty ? email : '使用者');

  PersonBrief get brief => PersonBrief(id: id, name: name, username: username, photoUrl: photoUrl, email: email);
}

/// admin_user() 多帶的群組
class AdminUserGroup {
  const AdminUserGroup({required this.id, required this.name, required this.isOwner});

  final String id;
  final String name;
  final bool isOwner;

  factory AdminUserGroup.fromJson(Map<String, dynamic> json) =>
      AdminUserGroup(id: asString(json['id']), name: asString(json['name']), isOwner: asBool(json['is_owner']));
}

class AdminUserDetail {
  const AdminUserDetail({required this.user, required this.groups});

  final AdminUser user;
  final List<AdminUserGroup> groups;

  factory AdminUserDetail.fromJson(Map<String, dynamic> json) => AdminUserDetail(
        user: AdminUser.fromJson(json),
        groups: asMapList(json['groups']).map(AdminUserGroup.fromJson).toList(),
      );
}

/// admin_users() 的一頁
class AdminUserPage {
  const AdminUserPage({required this.total, required this.users, this.siteOwnerId});

  final int total;
  final List<AdminUser> users;
  // 全站擁有者的 id（還沒有擁有者或舊的資料庫時是 null）
  final String? siteOwnerId;

  factory AdminUserPage.fromJson(Object? json) {
    final map = asMap(json);
    return AdminUserPage(
      total: asInt(map['total']),
      users: asMapList(map['users']).map(AdminUser.fromJson).toList(),
      siteOwnerId: asNullableString(map['site_owner_id']),
    );
  }

  /// 這位是不是全站擁有者（admin_user_json 的 is_owner，沒有時比對 site_owner_id）
  bool isOwner(AdminUser user) => user.isOwner ?? (siteOwnerId != null && siteOwnerId == user.id);
}

/// admin_user_totp() 的一筆：已加密的 secret 是 null
class AdminTotpItem {
  const AdminTotpItem({
    required this.id,
    required this.name,
    required this.category,
    required this.digits,
    required this.period,
    required this.algorithm,
    required this.pinned,
    required this.secret,
    required this.encrypted,
  });

  final String id;
  final String name;
  final String category;
  final int digits;
  final int period;
  final TotpAlgorithm algorithm;
  final bool pinned;
  final String? secret;
  final bool encrypted;

  factory AdminTotpItem.fromJson(Map<String, dynamic> json) {
    final encrypted = asBool(json['encrypted']);
    final secret = json['secret'];
    return AdminTotpItem(
      id: asString(json['id']),
      name: asString(json['name']),
      category: asString(json['category']),
      digits: asInt(json['digits'], TotpDefaults.digits),
      period: asInt(json['period'], TotpDefaults.period),
      algorithm: TotpAlgorithm.fromLabel(json['algorithm'] as String?),
      pinned: asBool(json['pinned']),
      secret: encrypted || secret is! String ? null : secret,
      encrypted: encrypted,
    );
  }

  AdminTotpItem copyWith({String? name, String? category, String? secret, int? digits, int? period, TotpAlgorithm? algorithm}) =>
      AdminTotpItem(
        id: id,
        name: name ?? this.name,
        category: category ?? this.category,
        digits: digits ?? this.digits,
        period: period ?? this.period,
        algorithm: algorithm ?? this.algorithm,
        pinned: pinned,
        secret: secret ?? this.secret,
        encrypted: encrypted,
      );
}

/// admin_groups() 的一筆
class AdminGroup {
  const AdminGroup({
    required this.id,
    required this.name,
    required this.description,
    required this.owner,
    required this.memberCount,
    required this.accountCount,
    required this.createdAt,
  });

  final String id;
  final String name;
  final String description;
  final PersonBrief? owner;
  final int memberCount;
  final int accountCount;
  final String? createdAt;

  factory AdminGroup.fromJson(Map<String, dynamic> json) => AdminGroup(
        id: asString(json['id']),
        name: asString(json['name']),
        description: asString(json['description']),
        owner: PersonBrief.fromJson(json['owner']),
        memberCount: asInt(json['member_count']),
        accountCount: asInt(json['account_count']),
        createdAt: asNullableString(json['created_at']),
      );
}

/// 操作紀錄（audit_page()；admin_audit_log、group_audit_log）
class AuditLog {
  const AuditLog({
    required this.id,
    required this.actor,
    required this.action,
    required this.targetType,
    required this.targetId,
    required this.detail,
    required this.createdAt,
  });

  final int id;
  // null：系統做的事，或做這件事的人已刪除帳號
  final PersonBrief? actor;
  final String action;
  final String? targetType;
  final String? targetId;
  final Map<String, dynamic> detail;
  final String createdAt;

  factory AuditLog.fromJson(Map<String, dynamic> json) => AuditLog(
        id: asInt(json['id']),
        actor: PersonBrief.fromJson(json['actor']),
        action: asString(json['action']),
        targetType: asNullableString(json['target_type']),
        targetId: asNullableString(json['target_id']),
        detail: asMap(json['detail']),
        createdAt: asString(json['created_at']),
      );
}

/// 一筆帳號操作紀錄（admin_user_activity / user_activity_page）：操作紀錄再加上所屬群組
class AccountActivity {
  const AccountActivity({required this.log, required this.groupId, required this.groupName});

  final AuditLog log;
  final String? groupId;
  final String? groupName;

  int get id => log.id;

  factory AccountActivity.fromJson(Map<String, dynamic> json) {
    final group = json['group'];
    final map = group is Map ? asMap(group) : null;
    return AccountActivity(
      log: AuditLog.fromJson(json),
      groupId: map == null ? null : asNullableString(map['id']),
      groupName: map == null ? null : asNullableString(map['name']),
    );
  }
}

/// 一筆登入紀錄（admin_user_login_history / login_history_page）
class LoginRecord {
  const LoginRecord({
    required this.id,
    required this.createdAt,
    required this.ip,
    required this.device,
    required this.userAgent,
    required this.provider,
  });

  final int id;
  final String createdAt;
  // 管理員管不到對方（階層不比對方高）時是 null
  final String? ip;
  // 「OS · 瀏覽器」
  final String? device;
  final String? userAgent;
  // google / email
  final String? provider;

  factory LoginRecord.fromJson(Map<String, dynamic> json) => LoginRecord(
        id: asInt(json['id']),
        createdAt: asString(json['created_at']),
        // 空字串（未知 IP）和 null（不公開）要分開
        ip: json['ip'] is String ? json['ip'] as String : null,
        device: asNullableString(json['device']),
        userAgent: asNullableString(json['user_agent']),
        provider: asNullableString(json['provider']),
      );
}

// ---------- 群組（group_detail） ----------

class GroupInfo {
  const GroupInfo({
    required this.id,
    required this.name,
    required this.description,
    required this.ownerId,
    required this.createdAt,
    required this.encrypted,
  });

  final String id;
  final String name;
  final String description;
  final String ownerId;
  final String? createdAt;
  final bool encrypted;

  factory GroupInfo.fromJson(Map<String, dynamic> json) => GroupInfo(
        id: asString(json['id']),
        name: asString(json['name']),
        description: asString(json['description']),
        ownerId: asString(json['owner_id']),
        createdAt: asNullableString(json['created_at']),
        encrypted: asBool(json['encrypted']),
      );
}

class GroupMember {
  const GroupMember({
    required this.person,
    required this.roleIds,
    required this.joinedAt,
    required this.isOwner,
    required this.topPosition,
  });

  final PersonBrief person;
  final List<String> roleIds;
  final String? joinedAt;
  final bool isOwner;
  final int topPosition;

  String get id => person.id;

  factory GroupMember.fromJson(Map<String, dynamic> json) => GroupMember(
        person: PersonBrief.fromJson(json) ?? const PersonBrief(id: '', name: ''),
        roleIds: _stringList(json['role_ids']),
        joinedAt: asNullableString(json['joined_at']),
        isOwner: asBool(json['is_owner']),
        topPosition: asInt(json['top_position']),
      );
}

/// 有效的邀請連結（group_detail().invites）
class GroupInvite {
  const GroupInvite({
    required this.code,
    required this.createdBy,
    required this.createdAt,
    required this.expiresAt,
    required this.maxUses,
    required this.uses,
  });

  final String code;
  // null：建立的人已刪除帳號
  final PersonBrief? createdBy;
  final String? createdAt;
  // null：永不過期（舊的連結）
  final String? expiresAt;
  // null：不限次數
  final int? maxUses;
  final int uses;

  factory GroupInvite.fromJson(Map<String, dynamic> json) => GroupInvite(
        code: asString(json['code']),
        createdBy: PersonBrief.fromJson(json['created_by']),
        createdAt: asNullableString(json['created_at']),
        expiresAt: asNullableString(json['expires_at']),
        maxUses: json['max_uses'] == null ? null : asInt(json['max_uses']),
        uses: asInt(json['uses']),
      );
}

/// 等待回覆的電子郵件 / @ID 邀請（group_detail().email_invites）
class GroupEmailInvite {
  const GroupEmailInvite({required this.id, required this.email, required this.invitedBy, required this.createdAt});

  final String id;
  final String email;
  final PersonBrief? invitedBy;
  final String? createdAt;

  factory GroupEmailInvite.fromJson(Map<String, dynamic> json) => GroupEmailInvite(
        id: asString(json['id']),
        email: asString(json['email']),
        invitedBy: PersonBrief.fromJson(json['invited_by']),
        createdAt: asNullableString(json['created_at']),
      );
}

/// group_detail()：前台的群組管理與後台共用
class AdminGroupDetail {
  const AdminGroupDetail({
    required this.group,
    required this.isOwner,
    required this.isDefault,
    required this.ownedCount,
    required this.permissions,
    required this.topPosition,
    required this.roles,
    required this.members,
    this.invites = const [],
    this.emailInvites = const [],
    this.categoryOrder = const [],
  });

  final GroupInfo group;
  final bool isOwner;
  // 是不是我的預設群組
  final bool isDefault;
  // 我擁有幾個群組
  final int ownedCount;
  // 我在這個群組的權限（全站「管理所有群組」是全部）
  final int permissions;
  final int topPosition;
  // 由高到低，@everyone 在最後
  final List<Role> roles;
  final List<GroupMember> members;
  // 有「邀請成員」或「管理群組」才有，否則是空的
  final List<GroupInvite> invites;
  final List<GroupEmailInvite> emailInvites;
  // 類別的自訂順序（所有成員共用）；舊的資料庫沒有這個欄位時是空的
  final List<String> categoryOrder;

  factory AdminGroupDetail.fromJson(Object? json) {
    final map = asMap(json);
    return AdminGroupDetail(
      group: GroupInfo.fromJson(asMap(map['group'])),
      isOwner: asBool(map['is_owner']),
      isDefault: asBool(map['is_default']),
      ownedCount: asInt(map['owned_count']),
      permissions: asInt(map['permissions']),
      topPosition: asInt(map['top_position']),
      roles: asMapList(map['roles']).map(Role.fromJson).toList(),
      members: asMapList(map['members']).map(GroupMember.fromJson).toList(),
      invites: asMapList(map['invites']).map(GroupInvite.fromJson).toList(),
      emailInvites: asMapList(map['email_invites']).map(GroupEmailInvite.fromJson).toList(),
      categoryOrder: parseCategoryOrder(map['category_order']),
    );
  }
}

/// group_add_member() 的回傳：加入的使用者 id 與顯示名稱
class AddedMember {
  const AddedMember({required this.id, required this.name});

  final String id;
  final String? name;

  factory AddedMember.fromJson(Object? json) {
    final map = asMap(json);
    return AddedMember(id: asString(map['id']), name: asNullableString(map['name']));
  }
}

List<String> _stringList(Object? value) =>
    value is List ? value.map((e) => e?.toString() ?? '').where((e) => e.isNotEmpty).toList() : <String>[];
