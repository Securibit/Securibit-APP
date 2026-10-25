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
    this.photoCustom = false,
    this.bgPhotoUrl = '',
    this.phoneNumber = '',
    this.emailVerified = false,
    this.creationTime = '',
    this.lastLoginAt = '',
    this.lastLoginIp = '',
    this.lastLoginDevice = '',
  });

  final String uid;
  final String name;
  // 使用者自己取的 @ID（不含 @，沒有時為空字串）
  final String username;
  final String email;
  final String photoUrl;
  // 大頭照是自己上傳的（不是 Google 的）；同步 Google 資料時不蓋掉
  final bool photoCustom;
  // 金鑰加密設定，null 代表未啟用
  final VaultInfo? vault;
  final String? defaultGroupId;
  // 背景圖網址（沒有時為空字串）
  final String bgPhotoUrl;
  final String phoneNumber;
  final bool emailVerified;
  // 帳號建立時間（從 Firebase 搬來的帳號保留原本的時間）
  final String creationTime;
  // 最後一次登入的時間 / IP / 裝置（record-login 寫入）
  final String lastLoginAt;
  final String lastLoginIp;
  final String lastLoginDevice;

  // 顯示名稱：沒有名字時用 email
  String get displayName => name.isNotEmpty ? name : (email.isNotEmpty ? email : '使用者');

  factory Profile.fromJson(Map<String, dynamic> row) => Profile(
        uid: asString(row['id']),
        name: asString(row['name']),
        username: asString(row['username']),
        email: asString(row['email']),
        photoUrl: asString(row['photo_url']),
        photoCustom: asBool(row['photo_custom']),
        vault: VaultInfo.fromJson(row['vault']),
        defaultGroupId: asNullableString(row['default_group_id']),
        bgPhotoUrl: asString(row['bg_photo_url']),
        phoneNumber: asString(row['phone_number']),
        emailVerified: asBool(row['email_verified']),
        creationTime: asString(row['creation_time']),
        lastLoginAt: asString(row['last_login_at']),
        lastLoginIp: asString(row['last_login_ip']),
        lastLoginDevice: asString(row['last_login_device']),
      );

  // 離線快取用，欄位名稱同資料庫
  Map<String, dynamic> toJson() => {
        'id': uid,
        'name': name,
        'username': username,
        'email': email,
        'photo_url': photoUrl,
        'photo_custom': photoCustom,
        'vault': vault == null
            ? null
            : {'v': vault!.v, 'salt': vault!.salt, 'iterations': vault!.iterations, 'check': vault!.check},
        'default_group_id': defaultGroupId,
        'bg_photo_url': bgPhotoUrl,
        'phone_number': phoneNumber,
        'email_verified': emailVerified,
        'creation_time': creationTime,
        'last_login_at': lastLoginAt,
        'last_login_ip': lastLoginIp,
        'last_login_device': lastLoginDevice,
      };
}
