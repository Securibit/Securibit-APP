import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:securibit/features/admin/admin_format.dart';
import 'package:securibit/features/admin/admin_models.dart';
import 'package:securibit/features/admin/audit_text.dart';
import 'package:securibit/features/auth/profile.dart';
import 'package:securibit/features/profile/profile_models.dart';
import 'package:securibit/features/profile/profile_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show User;

/*
 * 個人資料：@ID 規則（對照網站 src/lib/totp/account.ts 的 usernameProblem）、@ID 欄位狀態、
 * 個人資料欄位檢查、同步 Google 資料、user_public 的解析、共同群組的管理選單、本人看的活動紀錄文字
 */

// 網站 account.ts 的保留字與訊息（網站改了這裡要一起改；旁邊有網站原始碼時下面的測試會直接比對）
const _webReserved = [
  'admin', 'administrator', 'root', 'system', 'securibit', 'everyone',
  'here', 'support', 'help', 'null', 'undefined',
  'me', 'u', 'api', 'auth', 'about', 'disclaimer', 'code', 'codes', 'addcode',
  'groups', 'group', 'invite', 'invites', 'invitation', 'invitations',
  'settings', 'setting', 'new', 'edit', 'login', 'logout', 'signin', 'signout', 'signup', 'register',
  'user', 'users', 'profile', 'profiles', 'mypage', 'update_info', 'account', 'accounts',
  'notifications', 'roles', 'audit', 'callback', 'static', 'public', 'assets',
  '_next', 'favicon.ico', 'robots.txt', 'sitemap.xml', 'manifest.json',
];
const _formatMessage = '@ID 只能使用 3～32 個英文小寫字母、數字、底線（_）或句點（.）';
const _uuidMessage = '@ID 不能是 UUID 的格式（32 位英數字）';
const _reservedMessage = '這個 @ID 是保留字，不能使用';

// 網站 usernameProblem 的逐字移植，用來對照 App 的實作
String? _webUsernameProblem(String name, Set<String> reserved) {
  if (!RegExp(r'^[a-z0-9_.]{3,32}$').hasMatch(name)) return _formatMessage;
  if (RegExp(r'^[0-9a-f]{32}$', caseSensitive: false).hasMatch(name) ||
      RegExp(r'[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}', caseSensitive: false).hasMatch(name)) {
    return _uuidMessage;
  }
  if (reserved.contains(name)) return _reservedMessage;
  return null;
}

// 各種邊界的 @ID
final _samples = [
  ..._webReserved,
  'andy', 'andy.chen', 'a_b', 'abc', 'ab', 'a', '', 'Andy', 'andy-chen', 'andy chen', '安迪', 'andy!',
  'a' * 32, 'a' * 33, '0123456789abcdef0123456789abcdef', '0123456789ABCDEF0123456789ABCDEF',
  '0123456789abcdef0123456789abcdeg', '123e4567-e89b-12d3-a456-426614174000', 'x123e4567-e89b-12d3-a456-426614174000',
  'admin1', 'admins', '.admin', 'me.', 'u_u', '...', '___', '12345678',
];

User _user(Map<String, dynamic> extra) => User.fromJson({
      'id': '11111111-2222-3333-4444-555555555555',
      'app_metadata': <String, dynamic>{},
      'aud': 'authenticated',
      'created_at': '2024-05-01T08:00:00Z',
      ...extra,
    })!;

AdminGroupDetail _detail({
  bool isOwner = false,
  int permissions = 0,
  int topPosition = 0,
  required List<Map<String, dynamic>> members,
}) =>
    AdminGroupDetail.fromJson({
      'group': {'id': 'g1', 'name': '團隊', 'owner_id': 'owner'},
      'is_owner': isOwner,
      'permissions': permissions,
      'top_position': topPosition,
      'roles': [],
      'members': members,
    });

void main() {
  group('@ID 規則對照網站', () {
    test('App 的 usernameProblem 和網站逐字移植的結果一致', () {
      final reserved = _webReserved.toSet();
      for (final name in _samples) {
        expect(usernameProblem(name), _webUsernameProblem(name, reserved), reason: '「$name」');
      }
      // 保留字裡格式不合的（太短）先回格式錯誤，其他都是保留字
      expect(usernameProblem('me'), _formatMessage);
      expect(usernameProblem('admin'), _reservedMessage);
      expect(usernameProblem('favicon.ico'), _reservedMessage);
      expect(usernameProblem('0123456789abcdef0123456789abcdef'), _uuidMessage);
    });

    // 旁邊有網站原始碼（~/Project/Securibit-Web）時，直接讀 account.ts 比對保留字與訊息
    final web = File('../Securibit-Web/src/lib/totp/account.ts');
    test('和網站原始碼的保留字、訊息一致', () {
      final source = web.readAsStringSync();
      final set = RegExp(r'RESERVED_USERNAMES = new Set\(\[([\s\S]*?)\]\)').firstMatch(source)!.group(1)!;
      final words = RegExp(r"'([^']*)'").allMatches(set).map((m) => m.group(1)!).toList();
      expect(words, _webReserved);
      expect(source, contains("USERNAME_FORMAT_MESSAGE = '$_formatMessage'"));
      expect(source, contains("USERNAME_UUID_MESSAGE = '$_uuidMessage'"));
      expect(source, contains("USERNAME_RESERVED_MESSAGE = '$_reservedMessage'"));
      expect(source, contains(r'USERNAME_PATTERN = /^[a-z0-9_.]{3,32}$/'));
    }, skip: web.existsSync() ? false : '找不到網站原始碼');

    test('輸入時的整理', () {
      expect(sanitizeUsernameInput(' @Andy Chen '), 'andychen');
      expect(sanitizeUsernameInput('@@andy'), '@andy');
      expect(normalizeUsername(' @Andy.Chen '), 'andy.chen');
    });
  });

  group('@ID 欄位狀態', () {
    test('沒改：不檢查，說明是目前的 @ID 或格式提示', () {
      final same = UsernameDraft(current: 'admin', input: 'Admin');
      // 舊的 @ID 後來變成保留字也不擋
      expect(same.changed, isFalse);
      expect(same.problem, isNull);
      expect(same.needCheck, isFalse);
      expect(same.description, '這是你目前的 @ID');
      expect(same.canSave, isFalse);
      expect(UsernameDraft(current: '', input: '').description, usernameFormatHint);
    });

    test('清空代表清除', () {
      final draft = UsernameDraft(current: 'andy', input: '');
      expect(draft.changed, isTrue);
      expect(draft.needCheck, isFalse);
      expect(draft.error, isNull);
      expect(draft.description, '儲存後會清除 @ID');
      expect(draft.canSave, isTrue);
    });

    test('格式錯誤：不查資料庫', () {
      final draft = UsernameDraft(current: '', input: 'ab');
      expect(draft.problem, _formatMessage);
      expect(draft.error, _formatMessage);
      expect(draft.needCheck, isFalse);
      expect(draft.canSave, isFalse);
    });

    test('查資料庫：檢查中、可以使用、已被使用、無法檢查', () {
      final pending = UsernameDraft(current: '', input: '@Andy');
      expect(pending.name, 'andy');
      expect(pending.needCheck, isTrue);
      expect(pending.description, '檢查中…');
      expect(pending.canSave, isFalse);

      // 舊的查詢結果對不上目前的輸入，不算數
      final stale = UsernameDraft(current: '', input: 'andy', check: const UsernameCheck(name: 'and', available: true));
      expect(stale.checked, isNull);
      expect(stale.canSave, isFalse);

      final ok = UsernameDraft(current: '', input: 'andy', check: const UsernameCheck(name: 'andy', available: true));
      expect(ok.error, isNull);
      expect(ok.description, '可以使用');
      expect(ok.canSave, isTrue);

      final taken = UsernameDraft(current: '', input: 'andy', check: const UsernameCheck(name: 'andy', available: false));
      expect(taken.error, '這個 @ID 已被使用');
      expect(taken.canSave, isFalse);

      final failed = UsernameDraft(
        current: '',
        input: 'andy',
        check: const UsernameCheck(name: 'andy', available: null, message: '無法連線到伺服器'),
      );
      expect(failed.error, '無法檢查：無法連線到伺服器');
      expect(failed.canSave, isFalse);
    });
  });

  group('個人資料', () {
    test('圖片網址：空的可以，否則要 http(s)', () {
      expect(isHttpUrl(''), isTrue);
      expect(isHttpUrl('  '), isTrue);
      expect(isHttpUrl('https://example.com/a.png'), isTrue);
      expect(isHttpUrl('http://example.com'), isTrue);
      expect(isHttpUrl('ftp://example.com/a.png'), isFalse);
      expect(isHttpUrl('example.com/a.png'), isFalse);
      expect(isHttpUrl('https://'), isFalse);
    });

    test('預設背景圖等於沒有設定', () {
      expect(visibleBgPhoto(''), isNull);
      expect(visibleBgPhoto(defaultBgPhoto), isNull);
      expect(visibleBgPhoto('https://example.com/bg.jpg'), 'https://example.com/bg.jpg');
    });

    test('profiles 資料列與離線快取', () {
      final row = {
        'id': 'u1',
        'name': 'Andy',
        'username': 'andy',
        'email': 'a@example.com',
        'photo_url': 'https://example.com/a.png',
        'bg_photo_url': 'https://example.com/bg.jpg',
        'phone_number': '0912-345-678',
        'email_verified': true,
        'creation_time': '2024-05-01T08:00:00Z',
        'last_login_at': '2026-10-20T01:02:03Z',
        'last_login_ip': '1.2.3.4',
        'last_login_device': 'macOS · Securibit',
        'vault': null,
        'default_group_id': 'g1',
      };
      final profile = Profile.fromJson(row);
      expect(profile.bgPhotoUrl, 'https://example.com/bg.jpg');
      expect(profile.phoneNumber, '0912-345-678');
      expect(profile.emailVerified, isTrue);
      expect(profile.lastLoginDevice, 'macOS · Securibit');
      final again = Profile.fromJson(profile.toJson());
      expect(again.toJson(), profile.toJson());

      // 舊版快取沒有新欄位：給空值
      final old = Profile.fromJson({'id': 'u1', 'name': 'Andy', 'email': 'a@example.com'});
      expect(old.bgPhotoUrl, '');
      expect(old.phoneNumber, '');
      expect(old.username, '');
    });

    test('同步 Google 資料：名稱、大頭照用 Google 的，沒有電話時保留', () {
      final now = DateTime.utc(2026, 10, 21, 12);
      final patch = googleProfilePatch(
        _user({
          'user_metadata': {'full_name': 'Andy Chen', 'name': 'Andy', 'avatar_url': 'https://g/a.png', 'picture': 'https://g/p.png'},
          'last_sign_in_at': '2026-10-21T11:00:00Z',
        }),
        now,
      );
      expect(patch['name'], 'Andy Chen');
      expect(patch['photo_url'], 'https://g/a.png');
      expect(patch.containsKey('phone_number'), isFalse);
      expect(patch['creation_time'], '2024-05-01T08:00:00Z');
      expect(patch['last_sign_in_time'], '2026-10-21T11:00:00Z');
      expect(patch['updated_at'], '2026-10-21T12:00:00.000Z');
      // email 由 ensure_profile 同步，不寫
      expect(patch.containsKey('email'), isFalse);

      // 只有 name / picture 時改用它們；有電話時一起寫
      final fallback = googleProfilePatch(
        _user({
          'user_metadata': {'name': 'Andy', 'picture': 'https://g/p.png'},
          'phone': '+886912345678',
        }),
        now,
      );
      expect(fallback['name'], 'Andy');
      expect(fallback['photo_url'], 'https://g/p.png');
      expect(fallback['phone_number'], '+886912345678');
      expect(fallback['last_sign_in_time'], '');

      // Google 沒給名稱與大頭照：保留原本的
      final empty = googleProfilePatch(_user({'user_metadata': <String, dynamic>{}}), now);
      expect(empty.containsKey('name'), isFalse);
      expect(empty.containsKey('photo_url'), isFalse);
    });
  });

  group('別人的個人頁面', () {
    test('分辨 id 與 @ID', () {
      expect(isUuid('123e4567-e89b-12d3-a456-426614174000'), isTrue);
      expect(isUuid('123E4567-E89B-12D3-A456-426614174000'), isTrue);
      expect(isUuid('andy'), isFalse);
      expect(isUuid('0123456789abcdef0123456789abcdef'), isFalse);
    });

    test('user_public', () {
      final user = UserPublic.fromJson({
        'id': 'u2',
        'name': '',
        'username': 'bob',
        'photo_url': null,
        'created_at': '2024-05-01 08:00:00+00',
        'site_roles': [
          {'id': 'r2', 'name': '版主', 'color': '#17ffac', 'position': 2},
          {'id': 'r1', 'name': '成員', 'color': '', 'position': 1},
        ],
        'shared_groups': [
          {'id': 'g1', 'name': '團隊'},
        ],
      });
      expect(user.displayName, '@bob');
      expect(user.photoUrl, isNull);
      expect(user.topPosition, 2);
      expect(user.sharedGroups.single.name, '團隊');
      final admin = user.toAdminUser();
      expect(admin.email, '');
      expect(admin.roleIds, ['r2', 'r1']);
      expect(admin.topPosition, 2);
      expect(UserPublic.fromJson({'id': 'u3', 'site_roles': [], 'shared_groups': []}).topPosition, 0);
      expect(UserPublic.fromJson({'id': 'u3'}).displayName, '這位使用者');
    });

    test('共同群組的管理選單', () {
      Map<String, dynamic> member(String id, {int top = 0, bool owner = false}) =>
          {'id': id, 'name': id, 'role_ids': [], 'is_owner': owner, 'top_position': top};

      // 不在群組裡了
      final gone = sharedGroupMenu(_detail(permissions: 1, members: [member('me')]), 'u2', siteSuper: false);
      expect(gone.actions, isEmpty);
      expect(gone.reason, '他已經不在這個群組');

      // 群組管理員、身分組比他高：兩個都能做
      final both = sharedGroupMenu(_detail(permissions: 1, topPosition: 3, members: [member('u2', top: 1)]), 'u2', siteSuper: false);
      expect(both.actions, [SharedGroupAction.roles, SharedGroupAction.kick]);
      expect(both.member?.id, 'u2');

      // 只有「移除成員」
      final kickOnly = sharedGroupMenu(_detail(permissions: 32, topPosition: 3, members: [member('u2', top: 1)]), 'u2', siteSuper: false);
      expect(kickOnly.actions, [SharedGroupAction.kick]);

      // 他的身分組不比我低
      final outranked = sharedGroupMenu(_detail(permissions: 1, topPosition: 1, members: [member('u2', top: 1)]), 'u2', siteSuper: false);
      expect(outranked.actions, isEmpty);
      expect(outranked.reason, '他的身分組比你高，無法管理');

      // 全站管理不受階層限制；擁有者一律不能管理
      final superUser = sharedGroupMenu(_detail(permissions: 1, members: [member('u2', top: 5)]), 'u2', siteSuper: true);
      expect(superUser.actions, [SharedGroupAction.roles, SharedGroupAction.kick]);
      final owner = sharedGroupMenu(_detail(permissions: 1, isOwner: false, members: [member('u2', owner: true)]), 'u2', siteSuper: true);
      expect(owner.reason, '他是群組擁有者，無法管理');

      // 管得到但沒有權限
      final noPerm = sharedGroupMenu(_detail(permissions: 2, isOwner: true, members: [member('u2')]), 'u2', siteSuper: false);
      expect(noPerm.reason, '沒有可用的操作');
    });
  });

  test('本人看的活動紀錄用「你」，後台用「他」', () {
    final activity = AccountActivity.fromJson({
      'id': 1,
      'actor': {'id': 'admin', 'name': '小明'},
      'action': 'site.user.totp.view',
      'detail': <String, dynamic>{},
      'created_at': '2026-10-21T00:00:00Z',
    });
    expect(describeActivity(activity, 'u1', self: true), '管理員 小明 查看了你的 2FA');
    expect(describeActivity(activity, 'u1'), '管理員 小明 查看了他的 2FA');
  });
}
