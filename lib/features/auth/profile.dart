import '../../core/json.dart';
import '../vault/vault_info.dart';

// profiles 資料列（網站 src/types/Profile/Profile.ts 用得到的欄位）
class Profile {
  const Profile({
    required this.uid,
    required this.name,
    required this.username,
    required this.email,
    required this.photoUrl,
    required this.vault,
    required this.defaultGroupId,
  });

  final String uid;
  final String name;
  // 使用者自己取的 @ID（不含 @，沒有時為空字串）
  final String username;
  final String email;
  final String photoUrl;
  // 金鑰加密設定，null 代表未啟用
  final VaultInfo? vault;
  final String? defaultGroupId;

  // 顯示名稱：沒有名字時用 email
  String get displayName => name.isNotEmpty ? name : (email.isNotEmpty ? email : '使用者');

  factory Profile.fromJson(Map<String, dynamic> row) => Profile(
        uid: asString(row['id']),
        name: asString(row['name']),
        username: asString(row['username']),
        email: asString(row['email']),
        photoUrl: asString(row['photo_url']),
        vault: VaultInfo.fromJson(row['vault']),
        defaultGroupId: asNullableString(row['default_group_id']),
      );

  // 離線快取用，欄位名稱同資料庫
  Map<String, dynamic> toJson() => {
        'id': uid,
        'name': name,
        'username': username,
        'email': email,
        'photo_url': photoUrl,
        'vault': vault == null
            ? null
            : {'v': vault!.v, 'salt': vault!.salt, 'iterations': vault!.iterations, 'check': vault!.check},
        'default_group_id': defaultGroupId,
      };
}
