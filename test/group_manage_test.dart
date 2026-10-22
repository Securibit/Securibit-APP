import 'package:flutter_test/flutter_test.dart';
import 'package:securibit/core/permissions.dart';
import 'package:securibit/features/admin/admin_models.dart';
import 'package:securibit/features/groups/group_models.dart';
import 'package:securibit/features/groups/manage/group_rules.dart';

/*
 * 群組管理：group_detail 的邀請、group_invite_info 的解析（照網站 database/init.sql 的 jsonb_build_object），
 * 以及分頁、刪除、轉移、邀請連結、排序的規則（同網站 GroupView、GroupSettings、GroupInvites、InviteClient）
 */

Map<String, dynamic> detailJson({
  bool isOwner = true,
  bool isDefault = false,
  int ownedCount = 2,
  int permissions = 511,
  bool encrypted = false,
  List<Map<String, dynamic>>? members,
}) =>
    {
      'group': {
        'id': 'g1',
        'name': '工程部',
        'description': '共用帳號',
        'owner_id': 'u1',
        'created_at': '2026-01-02T03:04:05+00:00',
        'encrypted': encrypted,
      },
      'is_owner': isOwner,
      'is_default': isDefault,
      'owned_count': ownedCount,
      'permissions': permissions,
      'top_position': 0,
      'roles': [
        {'id': 'r0', 'name': '@everyone', 'color': '', 'position': 0, 'permissions': 2, 'is_default': true, 'member_count': 2},
      ],
      'members': members ??
          [
            {'id': 'u1', 'name': 'Andy', 'username': 'andy', 'photo_url': null, 'role_ids': [], 'joined_at': null, 'is_owner': true, 'top_position': 0},
          ],
      'invites': [
        {
          'code': 'AbCdEfGh_-123456',
          'created_by': {'id': 'u1', 'name': 'Andy', 'username': 'andy', 'photo_url': null},
          'created_at': '2026-10-01T00:00:00+00:00',
          'expires_at': '2026-10-08T00:00:00+00:00',
          'max_uses': 5,
          'uses': 2,
        },
        {'code': 'oldcode123', 'created_by': null, 'created_at': null, 'expires_at': null, 'max_uses': null, 'uses': 7},
      ],
      'email_invites': [
        {
          'id': 'e1',
          'email': 'bob@example.com',
          'invited_by': {'id': 'u1', 'name': '', 'username': 'andy', 'photo_url': null},
          'created_at': '2026-10-02T00:00:00+00:00',
        },
      ],
    };

AdminGroupDetail detail({
  bool isOwner = true,
  bool isDefault = false,
  int ownedCount = 2,
  int permissions = 511,
  bool encrypted = false,
}) =>
    AdminGroupDetail.fromJson(detailJson(
      isOwner: isOwner,
      isDefault: isDefault,
      ownedCount: ownedCount,
      permissions: permissions,
      encrypted: encrypted,
    ));

Map<String, dynamic> member(String id, String name, {bool owner = false, int top = 0}) =>
    {'id': id, 'name': name, 'username': null, 'photo_url': null, 'role_ids': [], 'joined_at': null, 'is_owner': owner, 'top_position': top};

void main() {
  group('解析', () {
    test('group_detail 的 invites 與 email_invites', () {
      final d = detail();
      expect(d.invites, hasLength(2));
      final first = d.invites.first;
      expect(first.code, 'AbCdEfGh_-123456');
      expect(first.createdBy?.id, 'u1');
      expect(first.maxUses, 5);
      expect(first.uses, 2);
      final old = d.invites.last;
      expect(old.createdBy, isNull);
      expect(old.maxUses, isNull);
      expect(old.expiresAt, isNull);
      expect(d.emailInvites.single.email, 'bob@example.com');
      expect(d.emailInvites.single.invitedBy?.username, 'andy');
    });

    test('沒有邀請權限時 invites 是空陣列；舊資料沒有這兩個欄位也不會壞', () {
      final json = detailJson()..remove('invites')..remove('email_invites');
      final d = AdminGroupDetail.fromJson(json);
      expect(d.invites, isEmpty);
      expect(d.emailInvites, isEmpty);
    });

    test('group_invite_info', () {
      final ok = InviteInfo.fromJson({
        'valid': true,
        'reason': null,
        'group': {'id': 'g1', 'name': '工程部', 'description': '', 'member_count': 3},
        'inviter': {'id': 'u1', 'name': '', 'username': 'andy', 'photo_url': null},
        'already_member': false,
      });
      expect(ok.usable, isTrue);
      expect(ok.group?.memberCount, 3);
      expect(inviterName(ok.inviter), '@andy');

      final notFound = InviteInfo.fromJson({'valid': false, 'reason': 'not_found', 'group': null, 'inviter': null, 'already_member': false});
      expect(notFound.usable, isFalse);
      expect(inviteReason(notFound.reason), '找不到這個邀請連結');

      // 已經是成員時就算連結失效也可以前往群組
      final expiredMember = InviteInfo.fromJson({
        'valid': false,
        'reason': 'expired',
        'group': {'id': 'g1', 'name': '工程部', 'description': '', 'member_count': 3},
        'inviter': null,
        'already_member': true,
      });
      expect(expiredMember.usable, isTrue);
    });
  });

  group('分頁', () {
    test('全部權限：成員、身分組、邀請、設定、紀錄', () {
      expect(visibleTabs(detail()), GroupManageTab.values);
    });

    test('只有 @everyone 的基本權限：沒有邀請和紀錄', () {
      expect(visibleTabs(detail(isOwner: false, permissions: GroupPermission.viewCodes)), [
        GroupManageTab.members,
        GroupManageTab.roles,
        GroupManageTab.settings,
      ]);
    });

    test('邀請：要有邀請成員或管理群組，加密的群組不行', () {
      expect(canSeeInvites(GroupPermission.createInvite, encrypted: false), isTrue);
      expect(canSeeInvites(GroupPermission.manageGroup, encrypted: false), isTrue);
      expect(canSeeInvites(GroupPermission.viewCodes, encrypted: false), isFalse);
      expect(canSeeInvites(GroupPermission.administrator, encrypted: true), isFalse);
    });

    test('看不到的分頁回到成員；tab 參數照名稱', () {
      final d = detail(isOwner: false, permissions: GroupPermission.viewCodes);
      expect(activeTab(d, GroupManageTab.audit), GroupManageTab.members);
      expect(activeTab(d, GroupManageTab.settings), GroupManageTab.settings);
      expect(GroupManageTab.fromName('invites'), GroupManageTab.invites);
      expect(GroupManageTab.fromName('codes'), isNull);
      expect(GroupManageTab.fromName(null), isNull);
    });
  });

  group('設定', () {
    test('刪除：擁有者或全站管理員；預設群組、唯一擁有的群組不能刪', () {
      expect(canDeleteGroup(detail(isOwner: false), siteAdmin: false), isFalse);
      expect(canDeleteGroup(detail(isOwner: false), siteAdmin: true), isTrue);
      expect(deleteBlockedReason(detail(isDefault: true)), contains('預設群組'));
      expect(deleteBlockedReason(detail(ownedCount: 1)), contains('唯一擁有'));
      expect(deleteBlockedReason(detail()), isNull);
      // 管理員刪別人的群組不擋（資料庫會幫擁有者處理預設群組）
      expect(deleteBlockedReason(detail(isOwner: false, isDefault: true, ownedCount: 0)), isNull);
    });

    test('轉移：加密的群組不能轉；預設群組在只擁有一個時不能轉', () {
      expect(transferBlockedReason(detail(encrypted: true)), '加密的群組不能轉移擁有權');
      expect(transferBlockedReason(detail(isDefault: true, ownedCount: 1)), contains('另一個群組'));
      expect(transferBlockedReason(detail(isDefault: true, ownedCount: 2)), isNull);
      expect(transferBlockedReason(detail(ownedCount: 1)), isNull);
    });

    test('危險區塊的說明', () {
      expect(dangerNotes(detail(isOwner: false), canDelete: false), isNull);
      expect(
        dangerNotes(detail(isDefault: true, ownedCount: 2), canDelete: true),
        '擁有者不能離開群組，要先轉移擁有權或刪除群組；轉移後你的預設群組會改成你擁有的另一個群組；這是你的預設群組，要先把其他群組設為預設才能刪除',
      );
    });

    test('成員排序：擁有者、最高身分組、名稱', () {
      final d = AdminGroupDetail.fromJson(detailJson(members: [
        member('u3', 'Cathy'),
        member('u2', 'Bob', top: 2),
        member('u4', 'Adam'),
        member('u1', 'Zed', owner: true),
      ]));
      expect(sortMembers(d.members).map((m) => m.id), ['u1', 'u2', 'u4', 'u3']);
    });
  });

  group('邀請連結', () {
    test('完整網址', () {
      expect(inviteUrl('abc123', base: 'https://2fa.bityo.tw'), 'https://2fa.bityo.tw/invite/abc123');
      expect(inviteUrl('abc123', base: 'http://localhost:3000/'), 'http://localhost:3000/invite/abc123');
    });

    test('從貼上的內容取出代碼', () {
      expect(parseInviteCode('https://2fa.bityo.tw/invite/AbCdEfGh_-123456'), 'AbCdEfGh_-123456');
      expect(parseInviteCode('  https://2fa.bityo.tw/invite/AbCdEfGh?from=qr  '), 'AbCdEfGh');
      expect(parseInviteCode('http://localhost:3000/invite/oldcode123/'), 'oldcode123');
      expect(parseInviteCode('2fa.bityo.tw/invite/oldcode123#x'), 'oldcode123');
      expect(parseInviteCode('AbCdEfGh_-123456'), 'AbCdEfGh_-123456');
      expect(parseInviteCode(''), isNull);
      expect(parseInviteCode('otpauth://totp/GitHub?secret=ABC'), isNull);
      expect(parseInviteCode('有中文的字'), isNull);
      expect(parseInviteCode('https://2fa.bityo.tw/invite/ab%zzcdef'), isNull);
      expect(parseInviteCode('https://2fa.bityo.tw/invite/'), isNull);
    });

    test('剩餘次數與說明', () {
      final d = detail();
      expect(inviteRemainingText(d.invites.first), '剩 3 / 5 次');
      expect(inviteRemainingText(d.invites.last), '不限次數，已用 7 次');
      expect(inviteMeta(d.invites.last), startsWith('由 已刪除的使用者 建立・不限次數，已用 7 次・永不過期'));
      expect(byText(d.emailInvites.single.invitedBy), '由 @andy ');
    });

    test('選項：有效時間最長 30 天，次數可以不限', () {
      expect(inviteExpiryOptions.map((o) => o.$1), [1, 24, 168, 720]);
      expect(inviteUseOptions.map((o) => o.$1), [1, 5, 10, 25, null]);
      expect(inviteExpiryOptions.any((o) => o.$1 == defaultInviteExpiry), isTrue);
    });
  });

  group('我的群組順序', () {
    test('上移、下移；到頭或找不到時不動', () {
      final ids = ['a', 'b', 'c'];
      expect(moveGroupIds(ids, 'b', -1), ['b', 'a', 'c']);
      expect(moveGroupIds(ids, 'b', 1), ['a', 'c', 'b']);
      expect(moveGroupIds(ids, 'a', -1), isNull);
      expect(moveGroupIds(ids, 'c', 1), isNull);
      expect(moveGroupIds(ids, 'x', 1), isNull);
      // 不改到原本的清單
      expect(ids, ['a', 'b', 'c']);
    });
  });
}
