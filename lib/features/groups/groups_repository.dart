import '../../core/json.dart';
import '../../core/result.dart';
import '../../core/rpc.dart';
import '../admin/admin_models.dart';
import 'group_models.dart';

/*
 * 群組的 RPC（和網站 src/lib/groups/groups.ts、src/lib/groups/invites.ts 呼叫的完全相同），前台與後台共用。
 * 權限一律由資料庫檢查，這裡只負責呼叫與解析。
 */

// ---------- 我的群組 ----------

// 我所在的全部群組，照我自己排的順序（預設群組在我沒排過時排第一）
Future<Result<List<Map<String, dynamic>>>> loadMyGroupsRaw() => rpc('my_groups', asMapList);

List<GroupSummary> parseGroups(List<Map<String, dynamic>> rows) => rows.map(GroupSummary.fromJson).toList();

/// 調整我的群組順序：ids 是我所在的全部群組（由上到下），只影響自己看到的順序
Future<Result<void>> reorderMyGroups(List<String> ids) => rpcVoid('my_groups_reorder', {'ids': ids});

// ---------- 群組 ----------

/// 建立群組（全站「建立群組」）；回傳新群組 id
Future<Result<String>> createGroup(String name, String description) =>
    rpc('group_create', (data) => asString(data), {'name': name.trim(), 'description': description.trim()});

Future<Result<AdminGroupDetail>> loadGroupDetail(String gid) => rpc('group_detail', AdminGroupDetail.fromJson, {'gid': gid});

Future<Result<void>> updateGroup(String gid, String name, String description) =>
    rpcVoid('group_update', {'gid': gid, 'name': name.trim(), 'description': description.trim()});

Future<Result<void>> deleteGroup(String gid) => rpcVoid('group_delete', {'gid': gid});

Future<Result<void>> transferGroup(String gid, String newOwner) =>
    rpcVoid('group_transfer', {'gid': gid, 'new_owner': newOwner});

Future<Result<void>> leaveGroup(String gid) => rpcVoid('group_leave', {'gid': gid});

/// 設為我的預設群組（只能是自己擁有的群組）
Future<Result<void>> setDefaultGroup(String gid) => rpcVoid('group_set_default', {'gid': gid});

// ---------- 成員與身分組 ----------

Future<Result<void>> kickMember(String gid, String userId) => rpcVoid('group_kick', {'gid': gid, 'user_id': userId});

Future<Result<void>> setMemberRoles(String gid, String userId, List<String> roleIds) =>
    rpcVoid('group_set_member_roles', {'gid': gid, 'user_id': userId, 'role_ids': roleIds});

Future<Result<String>> createGroupRole(String gid, RoleInput input) => rpc(
      'group_role_create',
      (data) => asString(data),
      {'gid': gid, 'name': input.name.trim(), 'color': input.color, 'permissions': input.permissions},
    );

Future<Result<void>> updateGroupRole(String roleId, RoleInput input) => rpcVoid(
      'group_role_update',
      {'role_id': roleId, 'name': input.name.trim(), 'color': input.color, 'permissions': input.permissions},
    );

Future<Result<void>> deleteGroupRole(String roleId) => rpcVoid('group_role_delete', {'role_id': roleId});

Future<Result<void>> reorderGroupRoles(String gid, List<String> roleIds) =>
    rpcVoid('group_roles_reorder', {'gid': gid, 'role_ids': roleIds});

// ---------- 邀請 ----------

/// expiresInHours：最長 720（30 天）；maxUses：null 代表不限次數。回傳邀請碼
Future<Result<String>> createInvite(String gid, int expiresInHours, int? maxUses) => rpc(
      'group_invite_create',
      (data) => asString(data),
      {'gid': gid, 'expires_in_hours': expiresInHours, 'max_uses': maxUses},
    );

Future<Result<void>> revokeInvite(String code) => rpcVoid('group_invite_revoke', {'code': code});

Future<Result<InviteInfo>> loadInviteInfo(String code) => rpc('group_invite_info', InviteInfo.fromJson, {'code': code});

/// 用邀請連結加入，回傳加入的群組 id（已經是成員時也回傳群組 id）
Future<Result<String>> joinGroup(String code) => rpc('group_join', (data) => asString(data), {'code': code});

/// target：電子郵件或 @ID
Future<Result<void>> inviteUser(String gid, String target) =>
    rpcVoid('group_invite_user', {'gid': gid, 'target': target.trim()});

Future<Result<void>> cancelEmailInvite(String inviteId) =>
    rpcVoid('group_email_invite_cancel', {'invite_id': inviteId});

// 寄給我（email）的群組邀請
Future<Result<List<Invitation>>> loadMyInvitations() =>
    rpc('my_invitations', (data) => asMapList(data).map(Invitation.fromJson).toList());

// 接受時回傳群組 id，拒絕回傳 null
Future<Result<String?>> respondInvitation(String inviteId, {required bool accept}) =>
    rpc('respond_invitation', (data) => data is String ? data : null, {'invite_id': inviteId, 'accept': accept});

// ---------- 操作紀錄 ----------

const auditPageSize = 50;

Future<Result<List<AuditLog>>> loadGroupAuditLog(String gid, int? beforeId, [int pageSize = auditPageSize]) => rpc(
      'group_audit_log',
      (data) => asMapList(data).map(AuditLog.fromJson).toList(),
      {'gid': gid, 'before_id': beforeId, 'page_size': pageSize},
    );
