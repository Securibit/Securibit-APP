import 'package:flutter_test/flutter_test.dart';
import 'package:securibit/features/admin/admin_models.dart';
import 'package:securibit/features/admin/admin_repository.dart';
import 'package:securibit/features/admin/audit_text.dart';
import 'package:securibit/features/codes/totp/totp_params.dart';

/*
 * 解析：輸入照 migration 裡各個函式的 jsonb_build_object 寫（admin_user_json、site_roles_list、
 * admin_groups、audit_page、login_history_page、user_activity_page、group_detail、admin_user_totp、me_permissions）
 */
void main() {
  test('me_permissions', () {
    final access = SiteAccess.fromJson({
      'permissions': 1023,
      'top_position': 3,
      'roles': [
        {'id': 'r1', 'name': '管理員', 'color': '#17ffac', 'position': 3},
      ],
    });
    expect(access.permissions, 1023);
    expect(access.topPosition, 3);
    expect(access.roles.single.color, '#17ffac');
    // 未登入時回傳 null
    expect(SiteAccess.fromJson(null).permissions, 0);
  });

  test('admin_users / admin_user', () {
    final userJson = {
      'id': 'u1',
      'email': 'a@example.com',
      'name': 'Andy',
      'username': null,
      'photo_url': null,
      'creation_time': '2024-05-01T08:00:00+00:00',
      'last_login_at': '2026-10-20T01:02:03.123456+00:00',
      'last_login_ip': null,
      'last_login_device': 'macOS · Chrome',
      'role_ids': ['r1', 'r2'],
      'top_position': 2,
      'totp_count': 7,
      'vault_enabled': true,
    };
    final page = AdminUserPage.fromJson({
      'total': 41,
      'users': [userJson],
    });
    expect(page.total, 41);
    final user = page.users.single;
    expect(user.username, isNull);
    // null（不公開）和空字串（沒有紀錄）要分開
    expect(user.lastLoginIp, isNull);
    expect(AdminUser.fromJson({...userJson, 'last_login_ip': ''}).lastLoginIp, '');
    expect(user.roleIds, ['r1', 'r2']);
    expect(user.totpCount, 7);
    expect(user.vaultEnabled, isTrue);

    final detail = AdminUserDetail.fromJson({
      ...userJson,
      'groups': [
        {'id': 'g1', 'name': 'Andy', 'is_owner': true},
      ],
    });
    expect(detail.groups.single.isOwner, isTrue);
    expect(detail.user.email, 'a@example.com');
  });

  test('admin_user_totp：已加密的沒有金鑰', () {
    final plain = AdminTotpItem.fromJson({
      'id': 'a1',
      'name': 'Google',
      'category': '工作,個人',
      'digits': 8,
      'period': 60,
      'algorithm': 'SHA-256',
      'pinned': true,
      'secret': 'JBSWY3DPEHPK3PXP',
      'encrypted': false,
    });
    expect(plain.secret, 'JBSWY3DPEHPK3PXP');
    expect(plain.algorithm, TotpAlgorithm.sha256);
    expect(plain.digits, 8);
    final locked = AdminTotpItem.fromJson({'id': 'a2', 'name': 'X', 'secret': null, 'encrypted': true, 'algorithm': 'SHA-1'});
    expect(locked.secret, isNull);
    expect(locked.encrypted, isTrue);
    expect(locked.digits, 6);
  });

  test('只送有變動的欄位', () {
    expect(buildTotpPatch(), isEmpty);
    expect(buildTotpPatch(name: '  Google ', secret: 'jbsw y3dp', algorithm: TotpAlgorithm.sha512), {
      'name': 'Google',
      'secret': 'JBSWY3DP',
      'algorithm': 'SHA-512',
    });
    expect(buildTotpPatch(category: ' 工作，個人 、工作'), {'category': '工作,個人'});
  });

  test('site_roles_list', () {
    final r = Role.fromJson({
      'id': 'r1',
      'name': '@everyone',
      'color': '',
      'position': 0,
      'permissions': 2,
      'is_default': true,
      'member_count': 20,
    });
    expect(r.isDefault, isTrue);
    expect(r.memberCount, 20);
    expect(r.input.sameAs(const RoleInput(name: '@everyone', color: '', permissions: 2)), isTrue);
    expect(const RoleInput(name: 'a', color: '#17FFAC', permissions: 1).sameAs(const RoleInput(name: 'a', color: '#17ffac', permissions: 1)), isTrue);
  });

  test('admin_groups：擁有者已刪除時是 null', () {
    final g = AdminGroup.fromJson({
      'id': 'g1',
      'name': '工程部',
      'description': '',
      'owner': null,
      'member_count': 3,
      'account_count': 12,
      'created_at': '2026-01-01T00:00:00+00:00',
    });
    expect(g.owner, isNull);
    expect(g.memberCount, 3);
  });

  test('audit_page：操作者是 null 時', () {
    final log = AuditLog.fromJson({
      'id': 99,
      'actor': null,
      'action': 'user.email',
      'target_type': 'user',
      'target_id': '7b0c2f5e-1111-2222-3333-444455556666',
      'detail': {'old': 'a@x.com', 'new': 'b@x.com'},
      'created_at': '2026-10-21T00:00:00+00:00',
    });
    expect(log.actor, isNull);
    expect(auditActionText(log.action), '變更電子郵件');
    expect(auditChangeText(log.action, log.detail), 'a@x.com → b@x.com');
    expect(auditTargetText(log), '使用者 7b0c2f5e…');
    expect(auditActionText('unknown.action'), 'unknown.action');
  });

  test('login_history_page：IP 是 null 代表不公開', () {
    final hidden = LoginRecord.fromJson({'id': 1, 'created_at': 'x', 'ip': null, 'device': null, 'user_agent': null, 'provider': 'google'});
    expect(loginIpText(hidden.ip), 'IP 不公開');
    expect(loginIpText(''), '未知 IP');
    expect(loginIpText('1.2.3.4'), '1.2.3.4');
    expect(providerText(hidden.provider), 'Google');
    expect(providerText(null), '未知方式');
  });

  test('user_activity_page 與中文描述（後台用「他」）', () {
    AccountActivity make(String action, Map<String, dynamic> detail, {Map<String, dynamic>? actor, Map<String, dynamic>? group}) =>
        AccountActivity.fromJson({
          'id': 1,
          'actor': actor,
          'action': action,
          'target_type': 'user',
          'target_id': 'u1',
          'detail': detail,
          'group': group,
          'created_at': '2026-10-21T00:00:00+00:00',
        });
    final admin = {'id': 'admin', 'name': '小明', 'username': null, 'photo_url': null};
    final self = {'id': 'u1', 'name': 'Andy', 'username': 'andy', 'photo_url': null};

    expect(describeActivity(make('user.username', {'old': 'andy', 'new': 'andy.chen'}, actor: self), 'u1'), '@ID 從 andy 改成 andy.chen');
    expect(describeActivity(make('user.name', {'old': null, 'new': 'Andy'}, actor: admin), 'u1'), '設定名稱為「Andy」（由 小明）');
    expect(describeActivity(make('user.email', {'old': 'a@x', 'new': 'b@x'}), 'u1'), '電子郵件從 a@x 改成 b@x（從登入帳號同步）');
    expect(
      describeActivity(make('site.user.roles', {'added_names': ['版主'], 'removed_names': []}, actor: admin), 'u1'),
      '管理員 小明 指派身分組 「版主」',
    );
    expect(describeActivity(make('site.user.totp.view', {}, actor: admin), 'u1'), '管理員 小明 查看了他的 2FA');
    final added = make('group.member.add', {}, actor: admin, group: {'id': 'g1', 'name': '工程部'});
    expect(added.groupName, '工程部');
    expect(describeActivity(added, 'u1'), '管理員 小明 把他加入群組「工程部」');
    expect(describeActivity(make('group.member.leave', {'name': '舊群組'}, actor: self), 'u1'), '離開群組「舊群組」');
  });

  test('group_detail 與 group_add_member', () {
    final detail = AdminGroupDetail.fromJson({
      'group': {
        'id': 'g1',
        'name': '工程部',
        'description': '共用帳號',
        'owner_id': 'u1',
        'created_at': '2026-01-01T00:00:00+00:00',
        'encrypted': false,
      },
      'is_owner': false,
      'is_default': false,
      'owned_count': 1,
      'permissions': 511,
      'top_position': 0,
      'roles': [
        {'id': 'r1', 'name': '版主', 'color': '#3b82f6', 'position': 1, 'permissions': 64, 'is_default': false, 'member_count': 1},
        {'id': 'r0', 'name': '@everyone', 'color': '', 'position': 0, 'permissions': 2, 'is_default': true, 'member_count': 2},
      ],
      'members': [
        {
          'id': 'u1',
          'name': 'Andy',
          'username': 'andy',
          'photo_url': null,
          'email': 'a@x.com',
          'role_ids': ['r1'],
          'joined_at': '2026-01-01T00:00:00+00:00',
          'is_owner': true,
          'top_position': 1,
        },
      ],
      'invites': [],
      'email_invites': [],
    });
    expect(detail.group.description, '共用帳號');
    expect(detail.permissions, 511);
    expect(detail.roles, hasLength(2));
    final member = detail.members.single;
    expect(member.id, 'u1');
    expect(member.person.email, 'a@x.com');
    expect(member.isOwner, isTrue);
    expect(member.roleIds, ['r1']);

    final added = AddedMember.fromJson({'id': 'u2', 'name': null});
    expect(added.id, 'u2');
    expect(added.name, isNull);
  });
}
