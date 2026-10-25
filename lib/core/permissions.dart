// 群組權限位元（與網站 src/lib/permissions/bits.ts、database/init.sql 一致）
class GroupPermission {
  GroupPermission._();

  static const administrator = 1;
  static const viewCodes = 2;
  static const viewSecrets = 4;
  static const manageCodes = 8;
  static const createInvite = 16;
  static const kickMembers = 32;
  static const manageRoles = 64;
  static const manageGroup = 128;
  static const viewAuditLog = 256;
  static const banMembers = 512;

  // 全部群組權限（資料庫 group_permissions 給擁有者的值）
  static const all = 1023;
}

/// 是否擁有某個權限（ADMINISTRATOR 一律通過）
bool hasPermission(int mask, int bit) => (mask & 1) != 0 || (mask & bit) == bit;
