// 全站與群組的權限定義（同網站 src/lib/permissions/bits.ts、migration 0009）
// 資料庫是 bigint，App 用 int；目前只用到 bit 0～9

/// 一個權限位元的顯示資料
class PermissionDef {
  const PermissionDef({required this.key, required this.bit, required this.name, required this.description});

  final String key;
  final int bit;
  final String name;
  final String description;
}

// ---------- 全站權限 ----------

class SitePermission {
  SitePermission._();

  static const administrator = 1;
  static const viewAdmin = 2;
  static const viewUsers = 4;
  static const manageUsers = 8;
  static const viewUserTotp = 16;
  static const manageUserTotp = 32;
  static const manageRoles = 64;
  static const viewAuditLog = 128;
  static const createGroups = 256;
  static const manageGroups = 512;

  static const all = 1023;
}

const sitePermissionDefs = <PermissionDef>[
  PermissionDef(key: 'ADMINISTRATOR', bit: SitePermission.administrator, name: '管理員', description: '擁有所有全站權限，且不受身分組階層限制。請只給信任的人。'),
  PermissionDef(key: 'VIEW_ADMIN', bit: SitePermission.viewAdmin, name: '進入後台', description: '可以開啟後台頁面。'),
  PermissionDef(key: 'VIEW_USERS', bit: SitePermission.viewUsers, name: '查看使用者', description: '查看使用者列表與基本資料。'),
  PermissionDef(key: 'MANAGE_USERS', bit: SitePermission.manageUsers, name: '管理使用者', description: '修改使用者名稱與 @ID、刪除使用者。'),
  PermissionDef(key: 'VIEW_USER_TOTP', bit: SitePermission.viewUserTotp, name: '查看使用者的 2FA', description: '查看使用者的金鑰與驗證碼（已啟用個人加密的看不到）。'),
  PermissionDef(key: 'MANAGE_USER_TOTP', bit: SitePermission.manageUserTotp, name: '管理使用者的 2FA', description: '修改、刪除使用者的驗證碼。'),
  PermissionDef(key: 'MANAGE_ROLES', bit: SitePermission.manageRoles, name: '管理身分組', description: '建立、編輯、刪除身分組，並指派給使用者。只能管理比自己低的身分組。'),
  PermissionDef(key: 'VIEW_AUDIT_LOG', bit: SitePermission.viewAuditLog, name: '查看操作紀錄', description: '查看全站的操作紀錄。'),
  PermissionDef(key: 'CREATE_GROUPS', bit: SitePermission.createGroups, name: '建立群組', description: '可以建立新的群組。'),
  PermissionDef(key: 'MANAGE_GROUPS', bit: SitePermission.manageGroups, name: '管理所有群組', description: '查看與管理所有群組，在任何群組內都擁有全部權限。'),
];

// ---------- 群組權限（位元值見 core/permissions.dart 的 GroupPermission） ----------

const groupPermissionDefs = <PermissionDef>[
  PermissionDef(key: 'ADMINISTRATOR', bit: 1, name: '群組管理員', description: '擁有所有群組權限，驗證碼的權限覆寫對他無效。'),
  PermissionDef(key: 'VIEW_CODES', bit: 2, name: '查看驗證碼', description: '看得到驗證碼與目前的動態碼，但拿不到金鑰。'),
  PermissionDef(key: 'VIEW_SECRETS', bit: 4, name: '查看金鑰', description: '查看、匯出金鑰（等於可以把驗證碼複製到自己的手機）。'),
  PermissionDef(key: 'MANAGE_CODES', bit: 8, name: '管理驗證碼', description: '新增、編輯、刪除、排序群組的驗證碼。'),
  PermissionDef(key: 'CREATE_INVITE', bit: 16, name: '邀請成員', description: '建立邀請連結，或用 Email / @ID 邀請別人。'),
  PermissionDef(key: 'KICK_MEMBERS', bit: 32, name: '移除成員', description: '把成員移出群組。只能移除身分組比自己低的成員。'),
  PermissionDef(key: 'MANAGE_ROLES', bit: 64, name: '管理身分組', description: '建立、編輯、指派身分組，並設定單筆驗證碼的權限。只能管理比自己低的身分組。'),
  PermissionDef(key: 'MANAGE_GROUP', bit: 128, name: '管理群組', description: '修改群組名稱與說明、撤銷別人建立的邀請。'),
  PermissionDef(key: 'VIEW_AUDIT_LOG', bit: 256, name: '查看操作紀錄', description: '查看這個群組的操作紀錄。'),
];

// ---------- 工具 ----------

/// ADMINISTRATOR 在全站與群組都是 1
const adminBit = 1;

/// 是否擁有某個權限（ADMINISTRATOR 一律通過）
bool hasBit(int mask, int bit) => (mask & adminBit) != 0 || (mask & bit) == bit;

/// 擁有其中任一個權限
bool hasAnyBit(int mask, List<int> bits) => bits.any((bit) => hasBit(mask, bit));

int toggleBit(int mask, int bit, bool on) => on ? mask | bit : mask & ~bit;

/// 已開啟的權限數
int countBits(int mask, List<PermissionDef> defs) => defs.where((def) => (mask & def.bit) != 0).length;

String permissionName(List<PermissionDef> defs, int bit) =>
    defs.where((def) => def.bit == bit).firstOrNull?.name ?? '$bit';
