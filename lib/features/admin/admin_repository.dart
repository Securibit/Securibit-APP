import '../../core/json.dart';
import '../../core/result.dart';
import '../../core/rpc.dart';
import '../codes/totp/categories.dart';
import '../codes/totp/secret.dart';
import '../codes/totp/totp_params.dart';
import '../groups/groups_repository.dart';
import 'admin_models.dart';

// 群組的 RPC 前台後台共用，放在 groups_repository；後台照舊用 repo.xxx 呼叫
export '../groups/groups_repository.dart'
    show
        auditPageSize,
        createGroup,
        createGroupRole,
        deleteGroup,
        deleteGroupRole,
        kickMember,
        loadGroupAuditLog,
        loadGroupDetail,
        reorderGroupRoles,
        setMemberRoles,
        transferGroup,
        updateGroup,
        updateGroupRole;

/*
 * 後台的 RPC 與 API（和網站 src/lib/admin/admin.ts、src/lib/users/activity.ts、src/lib/groups/groups.ts 呼叫的完全相同）。
 * 權限一律由資料庫檢查，這裡只負責呼叫與解析。
 */

// ---------- 自己的全站權限 ----------

Future<Result<SiteAccess>> loadSiteAccess() => rpc('me_permissions', SiteAccess.fromJson);

// ---------- 使用者 ----------

Future<Result<AdminUserPage>> loadAdminUsers(String search, int offset, int pageSize) => rpc(
      'admin_users',
      AdminUserPage.fromJson,
      {'search': search.trim().isEmpty ? null : search.trim(), 'page_offset': offset, 'page_size': pageSize},
    );

Future<Result<AdminUserDetail?>> loadAdminUser(String userId) =>
    rpc('admin_user', (data) => data is Map ? AdminUserDetail.fromJson(asMap(data)) : null, {'user_id': userId});

/// name / username：null 代表不改；username 空字串代表清除
Future<Result<void>> updateAdminUser(String userId, {String? name, String? username}) =>
    rpcVoid('admin_update_user', {'user_id': userId, 'name': name, 'username': username});

/// 刪除使用者走網站的 API（要用 service role 刪 auth 使用者），權限由網站先以我的身分檢查
Future<Result<void>> deleteAdminUser(String userId) async {
  final result = await callWebApi('/api/admin/delete-user', {'userId': userId});
  return switch (result) {
    Ok() => const Ok(null),
    Err(:final message, :final offline) => Err(message, offline: offline),
  };
}

// ---------- 使用者的 2FA（預設群組） ----------

/// 每次載入資料庫都會記一筆「查看使用者的 2FA」
Future<Result<List<AdminTotpItem>>> loadAdminUserTotp(String userId) =>
    rpc('admin_user_totp', (data) => asMapList(data).map(AdminTotpItem.fromJson).toList(), {'user_id': userId});

/// 只送有變動的欄位（同網站 updateAdminUserTotp：名稱去空白、類別整理、金鑰正規化）
Map<String, dynamic> buildTotpPatch({
  String? name,
  String? category,
  String? secret,
  int? digits,
  int? period,
  TotpAlgorithm? algorithm,
}) =>
    {
      'name': ?name?.trim(),
      if (category != null) 'category': normalizeCategories(category),
      if (secret != null) 'secret': normalizeSecret(secret),
      'digits': ?digits,
      'period': ?period,
      if (algorithm != null) 'algorithm': algorithm.label,
    };

Future<Result<void>> updateAdminUserTotp(String userId, String itemId, Map<String, dynamic> patch) =>
    rpcVoid('admin_update_user_totp', {'user_id': userId, 'item_id': itemId, 'patch': patch});

Future<Result<void>> deleteAdminUserTotp(String userId, String itemId) =>
    rpcVoid('admin_delete_user_totp', {'user_id': userId, 'item_id': itemId});

// ---------- 登入紀錄與帳號操作紀錄（0014） ----------

Future<Result<List<LoginRecord>>> loadAdminUserLoginHistory(String userId, int? beforeId, int pageSize) => rpc(
      'admin_user_login_history',
      (data) => asMapList(data).map(LoginRecord.fromJson).toList(),
      {'user_id': userId, 'before_id': beforeId, 'page_size': pageSize},
    );

Future<Result<List<AccountActivity>>> loadAdminUserActivity(String userId, int? beforeId, int pageSize) => rpc(
      'admin_user_activity',
      (data) => asMapList(data).map(AccountActivity.fromJson).toList(),
      {'user_id': userId, 'before_id': beforeId, 'page_size': pageSize},
    );

// ---------- 全站身分組 ----------

Future<Result<List<Role>>> loadSiteRoles() => rpc('site_roles_list', (data) => asMapList(data).map(Role.fromJson).toList());

Future<Result<String>> createSiteRole(RoleInput input) => rpc(
      'site_role_create',
      (data) => asString(data),
      {'name': input.name.trim(), 'color': input.color, 'permissions': input.permissions},
    );

Future<Result<void>> updateSiteRole(String roleId, RoleInput input) => rpcVoid(
      'site_role_update',
      {'role_id': roleId, 'name': input.name.trim(), 'color': input.color, 'permissions': input.permissions},
    );

Future<Result<void>> deleteSiteRole(String roleId) => rpcVoid('site_role_delete', {'role_id': roleId});

/// roleIds：由高到低的完整順序（不含 @everyone）
Future<Result<void>> reorderSiteRoles(List<String> roleIds) => rpcVoid('site_roles_reorder', {'role_ids': roleIds});

Future<Result<void>> setUserSiteRoles(String userId, List<String> roleIds) =>
    rpcVoid('site_set_user_roles', {'user_id': userId, 'role_ids': roleIds});

// ---------- 群組 ----------

Future<Result<List<AdminGroup>>> loadAdminGroups(String search) => rpc(
      'admin_groups',
      (data) => asMapList(data).map(AdminGroup.fromJson).toList(),
      {'search': search.trim().isEmpty ? null : search.trim()},
    );

/// 全站「管理所有群組」直接把使用者加進群組（不用邀請，只在後台）；target：電子郵件、@ID 或使用者 ID
Future<Result<AddedMember>> addGroupMember(String gid, String target) async {
  final result = await rpc('group_add_member', AddedMember.fromJson, {'gid': gid, 'target': target.trim()});
  if (result case Err(:final message) when message.contains('「group_add_member」')) {
    return const Err('資料庫還沒更新，請先在 Supabase 執行 0017_admin_add_member.sql');
  }
  return result;
}

// ---------- 操作紀錄 ----------

Future<Result<List<AuditLog>>> loadAdminAuditLog(int? beforeId, [int pageSize = auditPageSize]) => rpc(
      'admin_audit_log',
      (data) => asMapList(data).map(AuditLog.fromJson).toList(),
      {'before_id': beforeId, 'page_size': pageSize},
    );
