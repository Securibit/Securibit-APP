import '../../core/json.dart';
import '../admin/admin_models.dart';

// my_groups() 的一筆（網站 src/types/Group/Group.ts 的 GroupSummary）
class GroupSummary {
  const GroupSummary({
    required this.id,
    required this.name,
    required this.description,
    required this.ownerId,
    required this.isOwner,
    required this.isDefault,
    required this.encrypted,
    required this.position,
    required this.memberCount,
    required this.accountCount,
    required this.permissions,
  });

  final String id;
  final String name;
  final String description;
  final String ownerId;
  final bool isOwner;
  // 是不是我的預設群組（「我的驗證碼」）
  final bool isDefault;
  // 已開啟加密（金鑰用擁有者的加密密碼加密，只有擁有者一個成員）
  final bool encrypted;
  // 我自己排的順序；my_groups 已照它排好
  final int position;
  final int memberCount;
  // 我看得到的驗證碼數
  final int accountCount;
  // 我在這個群組的基礎權限（已展開）
  final int permissions;

  factory GroupSummary.fromJson(Map<String, dynamic> json) => GroupSummary(
        id: asString(json['id']),
        name: asString(json['name']),
        description: asString(json['description']),
        ownerId: asString(json['owner_id']),
        isOwner: asBool(json['is_owner']),
        isDefault: asBool(json['is_default']),
        encrypted: asBool(json['encrypted']),
        position: asInt(json['position']),
        memberCount: asInt(json['member_count'], 1),
        accountCount: asInt(json['account_count']),
        permissions: asInt(json['permissions']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'owner_id': ownerId,
        'is_owner': isOwner,
        'is_default': isDefault,
        'encrypted': encrypted,
        'position': position,
        'member_count': memberCount,
        'account_count': accountCount,
        'permissions': permissions,
      };
}

// 使用者的基本資料（邀請人）
class UserBrief {
  const UserBrief({required this.id, required this.name, this.username, this.photoUrl});

  final String id;
  final String name;
  final String? username;
  final String? photoUrl;

  static UserBrief? fromJson(Object? json) {
    if (json is! Map) return null;
    final map = asMap(json);
    return UserBrief(
      id: asString(map['id']),
      name: asString(map['name']),
      username: asNullableString(map['username']),
      photoUrl: asNullableString(map['photo_url']),
    );
  }

  String get displayName => name.isNotEmpty ? name : (username != null ? '@$username' : '某位使用者');
}

// my_invitations() 的一筆
class Invitation {
  const Invitation({
    required this.id,
    required this.groupId,
    required this.groupName,
    required this.memberCount,
    required this.invitedBy,
  });

  final String id;
  final String groupId;
  final String groupName;
  final int memberCount;
  final UserBrief? invitedBy;

  factory Invitation.fromJson(Map<String, dynamic> json) {
    final group = asMap(json['group']);
    return Invitation(
      id: asString(json['id']),
      groupId: asString(group['id']),
      groupName: asString(group['name'], '群組'),
      memberCount: asInt(group['member_count']),
      invitedBy: UserBrief.fromJson(json['invited_by']),
    );
  }
}

// 邀請連結指到的群組（group_brief()）
class GroupBrief {
  const GroupBrief({required this.id, required this.name, required this.description, required this.memberCount});

  final String id;
  final String name;
  final String description;
  final int memberCount;

  static GroupBrief? fromJson(Object? json) {
    if (json is! Map) return null;
    final map = asMap(json);
    return GroupBrief(
      id: asString(map['id']),
      name: asString(map['name'], '群組'),
      description: asString(map['description']),
      memberCount: asInt(map['member_count']),
    );
  }
}

// group_invite_info()：連結能不能用、指到哪個群組、誰建立的、我是不是已經在裡面
class InviteInfo {
  const InviteInfo({
    required this.valid,
    required this.reason,
    required this.group,
    required this.inviter,
    required this.alreadyMember,
    this.banned = false,
  });

  final bool valid;
  // not_found / revoked / expired / used_up
  final String? reason;
  final GroupBrief? group;
  final UserBrief? inviter;
  final bool alreadyMember;
  // 我被這個群組封鎖了（不能加入）
  final bool banned;

  factory InviteInfo.fromJson(Object? json) {
    final map = asMap(json);
    return InviteInfo(
      valid: asBool(map['valid']),
      reason: asNullableString(map['reason']),
      group: GroupBrief.fromJson(map['group']),
      inviter: UserBrief.fromJson(map['inviter']),
      alreadyMember: asBool(map['already_member']),
      banned: asBool(map['banned']),
    );
  }

  // 已經是成員時就算連結失效也可以直接前往群組
  // 被封鎖時不能加入
  bool get usable => group != null && (alreadyMember || (valid && !banned));
}

// group_bans() 的一筆：被封鎖的使用者（email 只有看得到成員 email 的人才有）
class GroupBan {
  const GroupBan({
    required this.person,
    required this.reason,
    required this.createdAt,
    required this.updatedAt,
    required this.bannedBy,
  });

  // id 是被封鎖的使用者 id
  final PersonBrief person;
  final String reason;
  final String? createdAt;
  final String? updatedAt;
  // 封鎖的人；帳號已刪除時是 null
  final PersonBrief? bannedBy;

  String get userId => person.id;

  factory GroupBan.fromJson(Map<String, dynamic> json) => GroupBan(
        person: PersonBrief(
          id: asString(json['user_id']),
          name: asString(json['name']),
          username: asNullableString(json['username']),
          photoUrl: asNullableString(json['photo_url']),
          email: asNullableString(json['email']),
        ),
        reason: asString(json['reason']),
        createdAt: asNullableString(json['created_at']),
        updatedAt: asNullableString(json['updated_at']),
        bannedBy: PersonBrief.fromJson(json['banned_by']),
      );
}
