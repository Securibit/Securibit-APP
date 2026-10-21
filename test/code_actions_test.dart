import 'package:flutter_test/flutter_test.dart';
import 'package:securibit/core/permissions.dart';
import 'package:securibit/features/admin/admin_models.dart';
import 'package:securibit/features/admin/hierarchy.dart';
import 'package:securibit/features/cache/offline_cache.dart';
import 'package:securibit/features/codes/code_models.dart';
import 'package:securibit/features/codes/codes_controller.dart';
import 'package:securibit/features/codes/codes_repository.dart';
import 'package:securibit/features/codes/totp/totp_params.dart';
import 'package:securibit/features/codes/widgets/overwrite_editor.dart';
import 'package:securibit/features/groups/group_models.dart';

GroupAccount account(String id, {bool pinned = false, int permissions = 0}) => GroupAccount(
      id: id,
      name: id,
      category: '',
      digits: 6,
      period: 30,
      algorithm: TotpAlgorithm.sha1,
      pinned: pinned,
      permissions: permissions,
      hasOverwrites: false,
    );

GroupSummary groupOf(String id, {int permissions = 0, bool encrypted = false, bool isOwner = true, int members = 1}) => GroupSummary(
      id: id,
      name: id,
      description: '',
      ownerId: 'owner',
      isOwner: isOwner,
      isDefault: false,
      encrypted: encrypted,
      position: 0,
      memberCount: members,
      accountCount: 0,
      permissions: permissions,
    );

Role role(String id, int position, {bool isDefault = false}) =>
    Role(id: id, name: id, color: '', position: position, permissions: 0, isDefault: isDefault, memberCount: 1);

GroupMember member(String id, {int top = 0, bool owner = false}) => GroupMember(
      person: PersonBrief(id: id, name: id),
      roleIds: const [],
      joinedAt: null,
      isOwner: owner,
      topPosition: top,
    );

Overwrite ow(OverwriteTargetType type, String id, {int allow = 0, int deny = 0}) =>
    Overwrite(targetType: type, targetId: id, allow: allow, deny: deny);

List<String> ids(List<GroupAccount> list) => list.map((a) => a.id).toList();

void main() {
  group('調整順序（同網站 GroupCodes 的 canSwap）', () {
    final ordered = [account('p1', pinned: true), account('p2', pinned: true), account('a'), account('b'), account('c')];

    test('同一區才能交換：釘選的和未釘選的不互換', () {
      expect(canSwapAccounts(ordered, 0, -1), isFalse);
      expect(canSwapAccounts(ordered, 0, 1), isTrue);
      expect(canSwapAccounts(ordered, 1, 1), isFalse);
      expect(canSwapAccounts(ordered, 2, -1), isFalse);
      expect(canSwapAccounts(ordered, 2, 1), isTrue);
      expect(canSwapAccounts(ordered, 4, 1), isFalse);
      expect(canSwapAccounts(ordered, 4, -1), isTrue);
      expect(canSwapAccounts(ordered, 9, -1), isFalse);
    });

    test('交換相鄰兩筆，不動原本的清單', () {
      expect(ids(swapAccounts(ordered, 2, 1)), ['p1', 'p2', 'b', 'a', 'c']);
      expect(ids(swapAccounts(ordered, 1, -1)), ['p2', 'p1', 'a', 'b', 'c']);
      expect(ids(ordered), ['p1', 'p2', 'a', 'b', 'c']);
    });
  });

  test('複製到其他群組：只列出有「管理驗證碼」的群組，不含來源群組', () {
    final groups = [
      groupOf('src', permissions: GroupPermission.manageCodes),
      groupOf('view', permissions: GroupPermission.viewCodes | GroupPermission.viewSecrets),
      groupOf('manage', permissions: GroupPermission.manageCodes),
      groupOf('admin', permissions: GroupPermission.administrator),
      groupOf('vault', permissions: 511, encrypted: true),
    ];
    expect(copyTargetGroups(groups, 'src').map((g) => g.id), ['manage', 'admin', 'vault']);
    expect(copyTargetGroups(const [], 'src'), isEmpty);
  });

  group('CodesController 的權限與排序', () {
    // 加密群組、不是擁有者：鎖定中，不會連線讀取
    CodesController controllerOf(int permissions) => CodesController(
          group: groupOf('g', permissions: permissions, encrypted: true, isOwner: false, members: 3),
          uid: 'u',
          vaultKeyId: null,
          cache: OfflineCache(),
        );

    test('排序、清空要群組層級的「管理驗證碼」；權限設定要「管理身分組」', () {
      final viewer = controllerOf(GroupPermission.viewCodes);
      addTearDown(viewer.dispose);
      viewer.accounts = [account('a'), account('b')];
      expect(viewer.canSort, isFalse);
      expect(viewer.canClear, isFalse);
      expect(viewer.canOverwrite, isFalse);

      final manager = controllerOf(GroupPermission.manageCodes | GroupPermission.manageRoles);
      addTearDown(manager.dispose);
      manager.accounts = [account('a')];
      expect(manager.canSort, isFalse, reason: '只有一筆沒有順序可以調');
      expect(manager.canClear, isTrue);
      expect(manager.canOverwrite, isTrue);
      manager.accounts = [account('a'), account('b')];
      expect(manager.canSort, isTrue);
      manager.accounts = const [];
      expect(manager.canClear, isFalse);

      // 離線時都不能改
      manager.accounts = [account('a'), account('b')];
      manager.offline = true;
      expect(manager.canSort, isFalse);
      expect(manager.canClear, isFalse);
      expect(manager.canOverwrite, isFalse);
    });

    test('沒有金鑰的不能匯出、不能複製', () async {
      final controller = controllerOf(GroupPermission.administrator);
      addTearDown(controller.dispose);
      controller.accounts = [account('a')];
      expect(controller.canExport(controller.accounts!.first), isFalse);
      expect(controller.canCopy(controller.accounts!.first), isFalse);
      expect(controller.exportable, isEmpty);
      expect(await controller.copyTo(controller.accounts!.first, groupOf('other')), isNotNull);
    });

    test('排序模式顯示全部（不套用搜尋與類別），釘選的在最上面', () {
      final controller = controllerOf(GroupPermission.manageCodes);
      addTearDown(controller.dispose);
      controller.accounts = [account('a'), account('pin', pinned: true), account('b')];
      controller.setKeyword('a');
      expect(ids(controller.filtered), ['a']);
      controller.setSorting(true);
      expect(ids(controller.filtered), ['pin', 'a', 'b']);
      controller.setSorting(false);
      expect(ids(controller.filtered), ['a']);
    });

    test('上下移先換畫面，寫入失敗就換回原本的順序', () async {
      final controller = controllerOf(GroupPermission.manageCodes);
      addTearDown(controller.dispose);
      controller.accounts = [account('a'), account('b'), account('c')];
      final changes = <List<String>>[];
      controller.addListener(() => changes.add(ids(controller.accounts!)));

      // 測試裡沒有連線（Supabase 沒有初始化），寫入一定失敗
      final error = await controller.reorder(1, 1);
      expect(error, isNotNull);
      expect(changes.first, ['a', 'c', 'b']);
      expect(ids(controller.accounts!), ['a', 'b', 'c']);

      // 不能交換的不送出
      changes.clear();
      expect(await controller.reorder(0, -1), isNull);
      expect(changes, isEmpty);
    });
  });

  group('權限覆寫（同網站 OverwriteEditor）', () {
    test('可以覆寫的只有查看驗證碼、查看金鑰、管理驗證碼', () {
      expect(overwritableBits, 14);
      expect(overwritePermissionDefs.map((d) => d.name), ['查看驗證碼', '查看金鑰', '管理驗證碼']);
    });

    test('允許／繼承／拒絕：拒絕優先，沒有設定是繼承', () {
      expect(overwriteState(null, 2), OverwriteState.inherit);
      final o = ow(OverwriteTargetType.role, 'r', allow: 2 | 8, deny: 4);
      expect(overwriteState(o, 2), OverwriteState.allow);
      expect(overwriteState(o, 4), OverwriteState.deny);
      expect(overwriteState(o, 8), OverwriteState.allow);
      expect(overwriteState(ow(OverwriteTargetType.role, 'r', allow: 4, deny: 4), 4), OverwriteState.deny);
      expect(overwriteCount(o), 3);
      expect(overwriteCount(ow(OverwriteTargetType.role, 'r', deny: 8)), 1);
      expect(overwriteCount(null), 0);
    });

    test('改一個權限只動那一個位元，允許和拒絕不會同時存在', () {
      expect(applyOverwriteState(allow: 0, deny: 0, bit: 4, state: OverwriteState.allow), (allow: 4, deny: 0));
      expect(applyOverwriteState(allow: 4, deny: 2, bit: 4, state: OverwriteState.deny), (allow: 0, deny: 6));
      expect(applyOverwriteState(allow: 6, deny: 8, bit: 2, state: OverwriteState.inherit), (allow: 4, deny: 8));
      expect(applyOverwriteState(allow: 0, deny: 8, bit: 8, state: OverwriteState.inherit), (allow: 0, deny: 0));
    });

    final roles = [role('everyone', 0, isDefault: true), role('low', 1), role('mid', 2), role('high', 3)];
    final members = [member('owner', top: 3, owner: true), member('alice', top: 1), member('bob', top: 3)];

    test('對象順序：@everyone → 有設定的身分組（由高到低）→ 成員', () {
      final targets = overwriteTargets(
        roles: roles,
        members: members,
        overwrites: [
          ow(OverwriteTargetType.member, 'bob', allow: 2),
          ow(OverwriteTargetType.role, 'low', deny: 4),
          ow(OverwriteTargetType.role, 'high', allow: 8),
        ],
        added: const [OverwriteTarget(OverwriteTargetType.member, 'alice')],
      );
      expect(targets.map((t) => '${t.type.value}:${t.id}'), ['role:everyone', 'role:high', 'role:low', 'member:alice', 'member:bob']);

      // 沒有任何設定時只有 @everyone
      expect(overwriteTargets(roles: roles, members: members, overwrites: const [], added: const []).length, 1);
    });

    test('還能加進來的對象：不含 @everyone、擁有者與已列出的', () {
      const shown = [OverwriteTarget(OverwriteTargetType.role, 'everyone'), OverwriteTarget(OverwriteTargetType.role, 'mid')];
      expect(addableRoles(roles, shown).map((r) => r.id), ['high', 'low']);
      expect(addableMembers(members, [...shown, const OverwriteTarget(OverwriteTargetType.member, 'bob')]).map((m) => m.id), ['alice']);
    });

    test('管得到才能改：@everyone 一律可以，其他要比自己最高的身分組低', () {
      const actor = Actor(unrestricted: false, topPosition: 2);
      bool can(OverwriteTargetType type, String id, [Actor a = actor]) =>
          canEditOverwriteTarget(a, OverwriteTarget(type, id), roles: roles, members: members);
      expect(can(OverwriteTargetType.role, 'everyone'), isTrue);
      expect(can(OverwriteTargetType.role, 'low'), isTrue);
      expect(can(OverwriteTargetType.role, 'mid'), isFalse);
      expect(can(OverwriteTargetType.role, 'high'), isFalse);
      expect(can(OverwriteTargetType.role, 'gone'), isFalse);
      expect(can(OverwriteTargetType.member, 'alice'), isTrue);
      expect(can(OverwriteTargetType.member, 'bob'), isFalse);
      // 擁有者、全站管理不受限
      expect(can(OverwriteTargetType.role, 'high', const Actor(unrestricted: true, topPosition: 0)), isTrue);
    });

    test('自己在這筆沒有的權限不能變更（不受限的例外）', () {
      const actor = Actor(unrestricted: false, topPosition: 2);
      const mine = GroupPermission.viewCodes | GroupPermission.manageCodes;
      expect(canChangeOverwriteBit(actor, mine, GroupPermission.viewCodes), isTrue);
      expect(canChangeOverwriteBit(actor, mine, GroupPermission.viewSecrets), isFalse);
      expect(canChangeOverwriteBit(const Actor(unrestricted: true, topPosition: 0), 0, GroupPermission.viewSecrets), isTrue);
    });
  });
}
