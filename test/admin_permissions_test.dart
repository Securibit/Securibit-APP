import 'package:flutter_test/flutter_test.dart';
import 'package:securibit/core/permissions.dart';
import 'package:securibit/features/admin/admin_format.dart';
import 'package:securibit/features/admin/admin_models.dart';
import 'package:securibit/features/admin/hierarchy.dart';
import 'package:securibit/features/admin/permission_defs.dart';

Role role(String id, int position, {int permissions = 0, bool isDefault = false, int members = 1, String color = ''}) => Role(
      id: id,
      name: id,
      color: color,
      position: position,
      permissions: permissions,
      isDefault: isDefault,
      memberCount: members,
    );

void main() {
  group('權限位元（同網站 bits.ts）', () {
    test('全站位元值', () {
      expect(SitePermission.administrator, 1);
      expect(SitePermission.viewAdmin, 2);
      expect(SitePermission.viewUsers, 4);
      expect(SitePermission.manageUsers, 8);
      expect(SitePermission.viewUserTotp, 16);
      expect(SitePermission.manageUserTotp, 32);
      expect(SitePermission.manageRoles, 64);
      expect(SitePermission.viewAuditLog, 128);
      expect(SitePermission.createGroups, 256);
      expect(SitePermission.manageGroups, 512);
      expect(SitePermission.sendNotifications, 1024);
      expect(SitePermission.all, 2047);
      expect(sitePermissionDefs.fold<int>(0, (m, d) => m | d.bit), SitePermission.all);
      expect(groupPermissionDefs.fold<int>(0, (m, d) => m | d.bit), GroupPermission.all);
      expect(GroupPermission.all, 1023);
      expect(GroupPermission.banMembers, 512);
    });

    test('hasBit：ADMINISTRATOR 一律通過', () {
      expect(hasBit(SitePermission.viewAdmin, SitePermission.viewAdmin), isTrue);
      expect(hasBit(SitePermission.viewAdmin, SitePermission.viewUsers), isFalse);
      expect(hasBit(SitePermission.administrator, SitePermission.manageGroups), isTrue);
      expect(hasAnyBit(SitePermission.viewUsers, [SitePermission.manageUsers, SitePermission.viewUsers]), isTrue);
    });

    test('toggleBit、countBits、permissionName', () {
      expect(toggleBit(0, 4, true), 4);
      expect(toggleBit(6, 4, false), 2);
      expect(countBits(2 | 4 | 512, sitePermissionDefs), 3);
      expect(permissionName(sitePermissionDefs, SitePermission.viewUsers), '查看使用者');
      expect(permissionName(sitePermissionDefs, 4096), '4096');
    });
  });

  group('階層（同網站 hierarchy.ts）', () {
    final roles = [role('top', 3, members: 1), role('mid', 2), role('low', 1), role('everyone', 0, isDefault: true, members: 9)];

    test('isSiteRoot：沒有任何「有人持有」的身分組比自己高', () {
      expect(isSiteRoot(3, roles), isTrue);
      expect(isSiteRoot(2, roles), isFalse);
      expect(isSiteRoot(0, roles), isFalse);
      // 最高的身分組沒人持有時，第二高的持有者就是最高位
      final emptyTop = [role('top', 3, members: 0), role('mid', 2)];
      expect(isSiteRoot(2, emptyTop), isTrue);
    });

    test('canManageRole：只能管比自己低的；@everyone 一律可以改權限', () {
      const actor = Actor(unrestricted: false, topPosition: 2);
      expect(canManageRole(actor, roles[0]), isFalse);
      expect(canManageRole(actor, roles[1]), isFalse);
      expect(canManageRole(actor, roles[2]), isTrue);
      expect(canManageRole(actor, roles[3]), isTrue);
      expect(canManageRole(const Actor(unrestricted: true, topPosition: 0), roles[0]), isTrue);
    });

    test('canManageMember：擁有者不能管；其他人看階層', () {
      const actor = Actor(unrestricted: false, topPosition: 2);
      expect(canManageMember(actor, topPosition: 1), isTrue);
      expect(canManageMember(actor, topPosition: 2), isFalse);
      expect(canManageMember(const Actor(unrestricted: true, topPosition: 0), topPosition: 5), isTrue);
      expect(canManageMember(const Actor(unrestricted: true, topPosition: 0), topPosition: 0, isOwner: true), isFalse);
    });

    test('canGrantRole：權限不能超過自己', () {
      expect(canGrantRole(2 | 4, role('a', 1, permissions: 4)), isTrue);
      expect(canGrantRole(2 | 4, role('a', 1, permissions: 8)), isFalse);
      expect(canGrantRole(SitePermission.all, role('a', 1, permissions: 1)), isTrue);
    });

    test('topPositionOf、sortRoles（@everyone 在最後）', () {
      expect(topPositionOf(['low', 'mid'], roles), 2);
      expect(topPositionOf([], roles), 0);
      final sorted = sortRoles([roles[3], roles[2], roles[0], roles[1]]);
      expect(sorted.map((r) => r.id), ['top', 'mid', 'low', 'everyone']);
    });

    test('上下移動：不能越過管不到的身分組', () {
      final ordered = roles.where((r) => !r.isDefault).toList();
      const actor = Actor(unrestricted: false, topPosition: 3);
      // mid 和 low 都比 3 低：可以互換
      expect(canMoveRole(actor, ordered, 1, 1), isTrue);
      expect(moveRole(ordered, 1, 1), ['top', 'low', 'mid']);
      // mid 往上會越過 top（不比自己低）
      expect(canMoveRole(actor, ordered, 1, -1), isFalse);
      // 超出範圍
      expect(canMoveRole(actor, ordered, 2, 1), isFalse);
      expect(canMoveRole(const Actor(unrestricted: true, topPosition: 0), ordered, 0, 1), isTrue);
    });
  });

  group('格式', () {
    test('@ID 規則（同資料庫 0013）', () {
      expect(normalizeUsername(' @Andy.Chen '), 'andy.chen');
      expect(usernameProblem('andy.chen'), isNull);
      expect(usernameProblem('ab'), contains('3～32'));
      expect(usernameProblem('Andy'), contains('小寫'));
      expect(usernameProblem('admin'), contains('保留字'));
      expect(usernameProblem('0123456789abcdef0123456789abcdef'), contains('UUID'));
    });

    test('身分組顏色', () {
      expect(parseRoleColor('#17ffac'), 0xFF17FFAC);
      expect(parseRoleColor(''), isNull);
      expect(parseRoleColor('#12345'), isNull);
      expect(normalizeRoleColor('17FFAC'), '#17ffac');
      expect(normalizeRoleColor('#zzzzzz'), isNull);
    });

    test('日期：沒有值是「無」，解析不了照原樣', () {
      expect(formatDateTime(null), '無');
      expect(formatDateTime('not a date'), 'not a date');
      final local = DateTime(2026, 1, 2, 3, 4, 5);
      expect(formatDateTime(local.toIso8601String()), '2026/01/02 03:04:05');
      expect(formatDate(local.toIso8601String()), '2026/01/02');
    });
  });
}
