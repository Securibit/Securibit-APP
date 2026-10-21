import '../../core/json.dart';

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
