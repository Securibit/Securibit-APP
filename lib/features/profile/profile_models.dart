import 'package:supabase_flutter/supabase_flutter.dart' show User;

import '../../core/json.dart';
import '../../core/permissions.dart';
import '../admin/admin_format.dart';
import '../admin/admin_models.dart';
import '../admin/hierarchy.dart';

/*
 * 個人資料用到的資料格式與檢查（同網站 src/lib/totp/account.ts、src/types/User/UserPublic.ts、
 * src/app/me/update_info/、src/app/u/[id]/）
 */

// ---------- 編輯個人資料 ----------

/// 上傳的圖片：大頭照或背景圖（網站 /api/profile/photo 的 kind）
enum PhotoKind {
  avatar('大頭照'),
  background('背景圖');

  const PhotoKind(this.label);

  final String label;
}

/// 名稱的長度上限（資料庫超過會截掉）
const profileNameMax = 64;

/// 上傳圖片的大小上限（同網站，8 MB）
const photoMaxBytes = 8 * 1024 * 1024;

const _imageTypes = {
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'png': 'image/png',
  'webp': 'image/webp',
  'gif': 'image/gif',
  'heic': 'image/heic',
  'heif': 'image/heif',
  'avif': 'image/avif',
  'bmp': 'image/bmp',
};

/// 依副檔名判斷圖片的類型；不是圖片時回傳 null
String? imageContentType(String filename) {
  final dot = filename.lastIndexOf('.');
  if (dot < 0) return null;
  return _imageTypes[filename.substring(dot + 1).toLowerCase()];
}


/// 同步 Google 資料時寫進 profiles 的欄位（同網站 syncGoogleUserData + toAppUser）：
/// 名稱、大頭照用 Google 的；Google 帳號沒有電話時保留使用者自己填的；email 由 ensure_profile 同步，這裡不寫。
/// Google 沒給名稱或大頭照時也保留原本的（網站會寫成 null）；自己上傳過大頭照（photoCustom）時不蓋掉大頭照。
/// 建立與最後登入時間由伺服器決定，不送
Map<String, dynamic> googleProfilePatch(User user, DateTime now, {bool photoCustom = false}) {
  final meta = user.userMetadata ?? const <String, dynamic>{};
  String? pick(List<String> keys) {
    for (final key in keys) {
      final value = meta[key];
      if (value is String && value.isNotEmpty) return value;
    }
    return null;
  }

  final name = pick(const ['full_name', 'name']);
  final photo = photoCustom ? null : pick(const ['avatar_url', 'picture']);
  final phone = user.phone;
  return {
    'name': ?name,
    'photo_url': ?photo,
    if (phone != null && phone.isNotEmpty) 'phone_number': phone,
    'updated_at': now.toUtc().toIso8601String(),
  };
}

// ---------- @ID ----------

/// 輸入 @ID 時即時整理：去掉空白與開頭的 @、轉小寫（同網站 UsernameSettings 的 onValueChange）
String sanitizeUsernameInput(String value) => value.replaceAll(RegExp(r'\s'), '').replaceFirst(RegExp(r'^@'), '').toLowerCase();

const usernameFormatHint = '3～32 字，只能用小寫英文、數字、底線、點';

/// 最後一次查詢 username_available 的結果；available 為 null 代表查詢失敗
class UsernameCheck {
  const UsernameCheck({required this.name, required this.available, this.message});

  final String name;
  final bool? available;
  final String? message;
}

/*
 * @ID 欄位的狀態（同網站 UsernameSettings）：
 * 沒改的不檢查（舊的 @ID 可能是後來才變成保留字）；有改、本地檢查通過才查資料庫；清空代表清除。
 */
class UsernameDraft {
  UsernameDraft({required this.current, required String input, this.check}) : name = normalizeUsername(input);

  final String current;
  // 正規化後的輸入
  final String name;
  final UsernameCheck? check;

  bool get changed => name != current;

  /// 格式、UUID 樣式、保留字（不用查資料庫）
  String? get problem => changed && name.isNotEmpty ? usernameProblem(name) : null;

  /// 要不要查資料庫
  bool get needCheck => changed && name.isNotEmpty && problem == null;

  // 查詢結果要對得上目前的輸入才算數
  UsernameCheck? get checked => check?.name == name ? check : null;

  /// 欄位的錯誤訊息；沒有錯誤是 null
  String? get error {
    if (problem != null) return problem;
    final result = checked;
    if (!needCheck || result == null) return null;
    if (result.available == false) return '這個 @ID 已被使用';
    if (result.available == null) return '無法檢查：${result.message ?? ''}';
    return null;
  }

  /// 欄位下方的說明（沒有錯誤時顯示）
  String get description {
    if (!changed) return current.isNotEmpty ? '這是你目前的 @ID' : usernameFormatHint;
    if (name.isEmpty) return '儲存後會清除 @ID';
    return checked?.available == true ? '可以使用' : '檢查中…';
  }

  bool get canSave => changed && (name.isEmpty || checked?.available == true);
}

// ---------- 別人的個人頁面 ----------

/// 共同群組
class SharedGroup {
  const SharedGroup({required this.id, required this.name});

  final String id;
  final String name;
}

/// user_public() 的回傳：別人的個人頁面看得到的公開資料（不含 email、電話、登入紀錄、驗證碼）
class UserPublic {
  const UserPublic({
    required this.id,
    required this.name,
    required this.username,
    required this.photoUrl,
    required this.createdAt,
    required this.siteRoles,
    required this.sharedGroups,
  });

  final String id;
  final String name;
  final String? username;
  final String? photoUrl;
  // 帳號建立時間
  final String? createdAt;
  // 全站身分組，不含 @everyone，由高到低
  final List<RoleBrief> siteRoles;
  // 我和對方同時是成員的群組
  final List<SharedGroup> sharedGroups;

  factory UserPublic.fromJson(Object? json) {
    final map = asMap(json);
    return UserPublic(
      id: asString(map['id']),
      name: asString(map['name']),
      username: asNullableString(map['username']),
      photoUrl: asNullableString(map['photo_url']),
      createdAt: asNullableString(map['created_at']),
      siteRoles: asMapList(map['site_roles']).map(RoleBrief.fromJson).toList(),
      sharedGroups: asMapList(map['shared_groups'])
          .map((g) => SharedGroup(id: asString(g['id']), name: asString(g['name'])))
          .toList(),
    );
  }

  /// 對方最高的全站身分組（沒有就是 0，同資料庫的 top_position）
  int get topPosition => siteRoles.fold(0, (top, role) => role.position > top ? role.position : top);

  /// 稱呼：名稱 → @ID → 這位使用者
  String get displayName => name.isNotEmpty ? name : (username != null ? '@$username' : '這位使用者');

  /// 沒有「查看使用者」拿不到 admin_user 時，用公開資料湊出編輯 / 刪除表單需要的欄位
  /// （沒有 email，刪除時改成輸入使用者 ID 確認）
  AdminUser toAdminUser() => AdminUser(
        id: id,
        email: '',
        name: name,
        username: username,
        photoUrl: photoUrl,
        creationTime: createdAt,
        lastLoginAt: null,
        lastLoginIp: null,
        lastLoginDevice: null,
        roleIds: [for (final role in siteRoles) role.id],
        topPosition: topPosition,
        totpCount: 0,
        vaultEnabled: false,
      );
}

/// 在共同群組裡管理對方的選項
enum SharedGroupAction { roles, kick }

/// 共同群組「…」選單的內容：可以做的操作，或為什麼不能管理
class SharedGroupMenu {
  const SharedGroupMenu({this.actions = const [], this.reason, this.member});

  final List<SharedGroupAction> actions;
  // 沒有可用的操作時的原因
  final String? reason;
  final GroupMember? member;
}

/// 依群組 detail 組出選單（同網站 SharedGroups 的 menuFor、群組頁的成員列表）；
/// siteSuper：全站管理員 / 管理所有群組，在任何群組都不受階層限制
SharedGroupMenu sharedGroupMenu(AdminGroupDetail detail, String targetId, {required bool siteSuper}) {
  final member = detail.members.where((m) => m.id == targetId).firstOrNull;
  if (member == null) return const SharedGroupMenu(reason: '他已經不在這個群組');
  final actor = Actor(unrestricted: detail.isOwner || siteSuper, topPosition: detail.topPosition);
  final manageable = canManageMember(actor, topPosition: member.topPosition, isOwner: member.isOwner);
  final actions = [
    if (hasPermission(detail.permissions, GroupPermission.manageRoles) && manageable) SharedGroupAction.roles,
    if (hasPermission(detail.permissions, GroupPermission.kickMembers) && manageable) SharedGroupAction.kick,
  ];
  if (actions.isNotEmpty) return SharedGroupMenu(actions: actions, member: member);
  final reason = member.isOwner ? '他是群組擁有者，無法管理' : (manageable ? '沒有可用的操作' : '他的身分組比你高，無法管理');
  return SharedGroupMenu(reason: reason, member: member);
}
