import '../../../core/env.dart';
import '../../../core/permissions.dart';
import '../../admin/admin_format.dart';
import '../../admin/admin_models.dart';
import '../group_models.dart';

/*
 * 群組管理畫面用到的規則（同網站 GroupView、GroupSettings、GroupInvites、InviteClient 的判斷），
 * 只用來決定按鈕要不要顯示、提示文字；真正的檢查在資料庫的 RPC。
 */

// 與資料庫的 check 一致
const groupNameMax = 50;
const groupDescriptionMax = 300;

/// 群組管理的分頁（名稱同 openGroupManage 的 tab 參數）
enum GroupManageTab {
  members('成員'),
  roles('身分組'),
  invites('邀請'),
  bans('封鎖名單'),
  settings('設定'),
  audit('紀錄');

  const GroupManageTab(this.label);

  final String label;

  static GroupManageTab? fromName(String? name) => values.where((t) => t.name == name).firstOrNull;
}

/// 能不能進「邀請」分頁：要有邀請成員或管理群組，而且加密的群組不能邀請其他人
bool canSeeInvites(int permissions, {required bool encrypted}) =>
    !encrypted && (hasPermission(permissions, GroupPermission.createInvite) || hasPermission(permissions, GroupPermission.manageGroup));

/// 能不能管理封鎖名單（加密的群組也可以，只是沒有其他成員）
bool canManageBans(int permissions) => hasPermission(permissions, GroupPermission.banMembers);

/// 看得到的分頁（成員、身分組、設定所有成員都有）
List<GroupManageTab> visibleTabs(AdminGroupDetail detail) => [
      GroupManageTab.members,
      GroupManageTab.roles,
      if (canSeeInvites(detail.permissions, encrypted: detail.group.encrypted)) GroupManageTab.invites,
      if (canManageBans(detail.permissions)) GroupManageTab.bans,
      GroupManageTab.settings,
      if (hasPermission(detail.permissions, GroupPermission.viewAuditLog)) GroupManageTab.audit,
    ];

/// 權限被拿掉時目前的分頁可能不見了，回到成員
GroupManageTab activeTab(AdminGroupDetail detail, GroupManageTab wanted) =>
    visibleTabs(detail).contains(wanted) ? wanted : GroupManageTab.members;

// ---------- 成員 ----------

/// 擁有者最前面，其餘依最高身分組、再依名稱
List<GroupMember> sortMembers(List<GroupMember> members) => [...members]..sort((a, b) {
    if (a.isOwner != b.isOwner) return a.isOwner ? -1 : 1;
    final byTop = b.topPosition - a.topPosition;
    return byTop != 0 ? byTop : a.person.displayName.compareTo(b.person.displayName);
  });

// ---------- 封鎖名單 ----------

// 與資料庫的 check 一致
const banReasonMax = 200;

/// 封鎖名單一列下面的灰字：「由 某人 封鎖・時間」，改過原因時加上修改時間
String banMeta(GroupBan ban) {
  final edited = ban.updatedAt != null && ban.updatedAt != ban.createdAt ? '・${formatDateTime(ban.updatedAt)} 修改' : '';
  return '${byText(ban.bannedBy)}封鎖・${formatDateTime(ban.createdAt)}$edited';
}

// ---------- 設定 ----------

/// 刪除群組：擁有者，或全站管理員
bool canDeleteGroup(AdminGroupDetail detail, {required bool siteAdmin}) => detail.isOwner || siteAdmin;

/// 擁有者不能刪自己的預設群組、也不能刪唯一擁有的群組（資料庫同樣檢查）；不是擁有者時不擋
String? deleteBlockedReason(AdminGroupDetail detail) {
  if (!detail.isOwner) return null;
  if (detail.isDefault) return '這是你的預設群組，要先把其他群組設為預設才能刪除';
  if (detail.ownedCount <= 1) return '這是你唯一擁有的群組，不能刪除';
  return null;
}

/// 轉移：加密的群組只有擁有者一個成員；預設群組會自動把預設改到自己擁有的另一個群組，沒有就不能轉
String? transferBlockedReason(AdminGroupDetail detail) {
  if (detail.group.encrypted) return '加密的群組不能轉移擁有權';
  if (detail.isDefault && detail.ownedCount <= 1) return '這是你唯一擁有的群組，要先建立另一個群組才能轉移';
  return null;
}

/// 設定分頁最下面危險區塊的說明（多條用「；」接起來）
String? dangerNotes(AdminGroupDetail detail, {required bool canDelete}) {
  final transferBlocked = transferBlockedReason(detail);
  final notes = [
    if (detail.isOwner) '擁有者不能離開群組，要先轉移擁有權或刪除群組',
    if (detail.isOwner && transferBlocked != null) transferBlocked,
    if (detail.isOwner && transferBlocked == null && detail.isDefault) '轉移後你的預設群組會改成你擁有的另一個群組',
    if (canDelete && deleteBlockedReason(detail) != null) deleteBlockedReason(detail)!,
  ];
  return notes.isEmpty ? null : notes.join('；');
}

// ---------- 邀請 ----------

/// 有效時間（小時）：最長 30 天（資料庫也會擋）
const inviteExpiryOptions = <(int, String)>[(1, '1 小時'), (24, '1 天'), (168, '7 天'), (720, '30 天')];

/// 使用次數，null = 不限
const inviteUseOptions = <(int?, String)>[(1, '1 次'), (5, '5 次'), (10, '10 次'), (25, '25 次'), (null, '不限次數')];

const defaultInviteExpiry = 168;

/// 邀請連結的完整網址（網站的 /invite/<code>）
String inviteUrl(String code, {String base = Env.webUrl}) {
  final root = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
  return '$root/invite/$code';
}

final _codePattern = RegExp(r'^[A-Za-z0-9_-]{6,64}$');

/// 從貼上的內容取出邀請碼：完整網址（…/invite/<code>，可帶查詢字串）或只有代碼；看不出來時回傳 null
String? parseInviteCode(String input) {
  var text = input.trim();
  if (text.isEmpty) return null;
  final marker = text.indexOf('/invite/');
  if (marker >= 0) {
    text = text.substring(marker + '/invite/'.length);
    final end = text.indexOf(RegExp(r'[/?#\s]'));
    if (end >= 0) text = text.substring(0, end);
  }
  // 邀請碼是 base64url（英數、- 與 _），不用解 % 編碼
  return _codePattern.hasMatch(text) ? text : null;
}

/// 邀請連結無法使用的原因（同網站 INVITE_REASON_TEXT）
const inviteReasonText = <String, String>{
  'not_found': '找不到這個邀請連結',
  'revoked': '這個邀請連結已被撤銷',
  'expired': '這個邀請連結已過期',
  'used_up': '這個邀請連結的使用次數已用完',
};

/// 被群組封鎖時的說明（group_invite_info 的 banned）
const bannedFromGroupText = '你已被這個群組封鎖';

String inviteReason(String? reason) => inviteReasonText[reason] ?? '這個邀請連結無法使用';

/// 「剩 3 / 5 次」或「不限次數，已用 2 次」
String inviteRemainingText(GroupInvite invite) {
  final max = invite.maxUses;
  if (max == null) return '不限次數，已用 ${invite.uses} 次';
  final left = max - invite.uses;
  return '剩 ${left < 0 ? 0 : left} / $max 次';
}

/// 「由 某人」：已刪除的使用者、沒有名稱時用 @ID
String byText(PersonBrief? person) {
  if (person == null) return '由 已刪除的使用者 ';
  final name = person.name.isNotEmpty ? person.name : (person.username != null ? '@${person.username}' : '成員');
  return '由 $name ';
}

/// 邀請連結下面那行灰字
String inviteMeta(GroupInvite invite) {
  final expires = invite.expiresAt == null ? '永不過期' : '${formatDateTime(invite.expiresAt)} 到期';
  return '${byText(invite.createdBy)}建立・${inviteRemainingText(invite)}・$expires';
}

/// 邀請人的稱呼
String? inviterName(UserBrief? inviter) {
  if (inviter == null) return null;
  return inviter.name.isNotEmpty ? inviter.name : (inviter.username != null ? '@${inviter.username}' : '成員');
}

// ---------- 我的群組順序 ----------

/// 把 gid 往上（-1）或往下（+1）移一格，回傳新的 id 順序；移不動時回傳 null
List<String>? moveGroupIds(List<String> ids, String gid, int offset) {
  final index = ids.indexOf(gid);
  final target = index + offset;
  if (index < 0 || target < 0 || target >= ids.length) return null;
  final next = [...ids];
  next[index] = ids[target];
  next[target] = gid;
  return next;
}
