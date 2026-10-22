import 'package:supabase_flutter/supabase_flutter.dart' show SignOutScope;

import '../../core/json.dart';
import '../../core/result.dart';
import '../../core/rpc.dart';
import '../admin/admin_format.dart';
import '../admin/admin_models.dart';
import 'profile_models.dart';
import 'session_models.dart';

/*
 * 自己的個人資料、@ID、活動紀錄與別人的公開資料（同網站 src/lib/totp/account.ts、src/lib/users/）
 */

// ---------- 個人資料 ----------

/// 更新名稱、大頭照、背景圖、電話（RLS 只開放這幾個欄位給本人直接改；email 以登入帳號為準）
Future<Result<void>> updateProfile(
  String uid, {
  required String name,
  required String photoUrl,
  required String bgPhotoUrl,
  required String phoneNumber,
}) =>
    _updateRow(uid, {
      'name': name,
      'photo_url': photoUrl,
      'bg_photo_url': bgPhotoUrl,
      'phone_number': phoneNumber,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });

/// 用登入帳號（Google）的名稱與大頭照蓋掉目前的資料；背景圖與電話保留
Future<Result<void>> syncGoogleProfile() async {
  final user = supabase.auth.currentUser;
  if (user == null) return const Err('尚未登入');
  return _updateRow(user.id, googleProfilePatch(user, DateTime.now()));
}

Future<Result<void>> _updateRow(String uid, Map<String, dynamic> patch) async {
  try {
    await supabase.from('profiles').update(patch).eq('id', uid).timeout(const Duration(seconds: 20));
    return const Ok(null);
  } catch (error) {
    return errorResult(error);
  }
}

// ---------- @ID ----------

/// 設定自己的 @ID（空字串代表清除），回傳實際存進去的值（小寫，清除時是 null）
Future<Result<String?>> setUsername(String username) =>
    rpc('set_username', asNullableString, {'new_username': normalizeUsername(username)});

/// @ID 可不可以用（格式正確、不是保留字、沒人用）
Future<Result<bool>> usernameAvailable(String username) =>
    rpc('username_available', (data) => data == true, {'name': normalizeUsername(username)});

// ---------- 活動紀錄 ----------

Future<Result<List<LoginRecord>>> loadMyLoginHistory(int? beforeId, int pageSize) => rpc(
      'my_login_history',
      (data) => asMapList(data).map(LoginRecord.fromJson).toList(),
      {'before_id': beforeId, 'page_size': pageSize},
    );

Future<Result<List<AccountActivity>>> loadMyAccountActivity(int? beforeId, int pageSize) => rpc(
      'my_account_activity',
      (data) => asMapList(data).map(AccountActivity.fromJson).toList(),
      {'before_id': beforeId, 'page_size': pageSize},
    );

// ---------- 已登入的裝置 ----------

/// 自己所有登入中的 session（這台排第一）
Future<Result<List<SessionRecord>>> loadMySessions() => rpc(
      'list_my_sessions',
      (data) => asMapList(data).map(SessionRecord.fromJson).toList(),
    );

/// 登出某一台裝置（不能是這台）
Future<Result<void>> revokeMySession(String sessionId) => rpcVoid('revoke_my_session', {'session_id': sessionId});

/// 登出這台以外的所有裝置（Auth API，這台的 session 保留）
Future<Result<void>> signOutOtherSessions() async {
  try {
    await supabase.auth.signOut(scope: SignOutScope.others).timeout(const Duration(seconds: 20));
    return const Ok(null);
  } catch (error) {
    return errorResult(error);
  }
}

/// 記下目前這個 session 是哪台裝置（RLS 只允許寫自己目前的 session）
Future<Result<void>> saveSessionDevice({
  required String sessionId,
  required String userId,
  required String deviceName,
  required String platform,
  required String appVersion,
}) async {
  try {
    await supabase.from('session_devices').upsert({
      'session_id': sessionId,
      'user_id': userId,
      'device_name': deviceName,
      'platform': platform,
      'app_version': appVersion,
      'last_seen_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'session_id').timeout(const Duration(seconds: 20));
    return const Ok(null);
  } catch (error) {
    return errorResult(error);
  }
}

// ---------- 別人的公開資料 ----------

// 標準 UUID（8-4-4-4-12）；@ID 不能長這樣，所以用它分辨是 id 還是 @ID
final _uuidPattern = RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$', caseSensitive: false);

bool isUuid(String value) => _uuidPattern.hasMatch(value);

/// 別人的公開資料：參數是 UUID 就照 id 查，否則當 @ID 查
Future<Result<UserPublic>> loadUserPublic(String idOrUsername) {
  if (isUuid(idOrUsername)) return rpc('user_public', UserPublic.fromJson, {'user_id': idOrUsername});
  final name = normalizeUsername(idOrUsername);
  if (name.isEmpty) return Future.value(const Err('找不到這位使用者'));
  return rpc('user_public_by_username', UserPublic.fromJson, {'name': name});
}
