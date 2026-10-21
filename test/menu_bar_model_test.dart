import 'package:flutter_test/flutter_test.dart';
import 'package:securibit/features/codes/code_models.dart';
import 'package:securibit/features/codes/secret_handle.dart';
import 'package:securibit/features/codes/totp/otp.dart';
import 'package:securibit/features/groups/group_models.dart';
import 'package:securibit/features/menubar/menu_bar_model.dart';
import 'package:securibit/src/rust/api/secrets.dart';

// 選單列／系統匣共用的內容：分組、釘選順序、遮住驗證碼、鎖定與未登入，以及 Linux 用的一行文字
const _secret = 'JBSWY3DPEHPK3PXP';

// 金鑰放進 Rust 記憶體（每次一格新的 scope），回傳指向它的 handle
var _scopes = 0;
Map<String, SecretHandle> _secrets(Map<String, String> raw) {
  final scope = 'test:${_scopes++}';
  return SecretHandle.fromMetas(scope, secretsPut(scope: scope, raw: raw));
}
// 30 秒週期的第 5 秒（剩 25 秒）
const _now = 1700000005000 - 1700000005000 % 30000 + 5000;

GroupSummary _group(String id, String name, {bool encrypted = false, bool isOwner = true}) => GroupSummary.fromJson({
      'id': id,
      'name': name,
      'is_owner': isOwner,
      'encrypted': encrypted,
    });

GroupAccount _account(String id, String name, {bool pinned = false}) =>
    GroupAccount.fromJson({'id': id, 'name': name, 'pinned': pinned, 'digits': 6, 'period': 30});

MenuBarModel _build({
  bool signedIn = true,
  bool profileReady = true,
  bool appLocked = false,
  bool hideCodes = false,
  bool vaultUnlocked = false,
  List<GroupSummary>? groups,
  Map<String, MenuGroupData> data = const {},
  int now = _now,
  bool withCodes = true,
}) =>
    buildMenuBarModel(
      signedIn: signedIn,
      profileReady: profileReady,
      appLocked: appLocked,
      hideCodes: hideCodes,
      vaultUnlocked: vaultUnlocked,
      groups: groups,
      data: data,
      nowMs: now,
      withCodes: withCodes,
    );

void main() {
  final expected = generateOtp(secret: _secret, timestampMs: _now)!;

  group('分組', () {
    test('依群組順序分段，釘選的排在前面', () {
      final model = _build(
        groups: [_group('g2', '工作'), _group('g1', '我的驗證碼')],
        data: {
          'g1': MenuGroupData(accounts: [_account('a', 'GitHub'), _account('b', 'Google', pinned: true)], secrets: _secrets({'a': _secret, 'b': _secret})),
          'g2': MenuGroupData(accounts: [_account('c', 'AWS')], secrets: _secrets({'c': _secret})),
        },
      );
      expect(model.status, MenuBarStatus.ready);
      expect(model.sections.map((s) => s.title), ['工作', '我的驗證碼']);
      expect(model.sections[1].items.map((i) => i.name), ['Google', 'GitHub']);
      expect(model.sections[1].items.first.id, 'g1/b');
      expect(model.submenus, isFalse);
      expect(model.showSettings, isTrue);
    });

    test('驗證碼依 App 的格式排版，剩餘秒數與快到期', () {
      final model = _build(
        groups: [_group('g1', '我的驗證碼')],
        data: {'g1': MenuGroupData(accounts: [_account('a', 'GitHub')], secrets: _secrets({'a': _secret}))},
      );
      final item = model.items.single;
      expect(item.code, formatOtp(expected));
      expect(item.remaining, '25 秒');
      expect(item.expiring, isFalse);
      expect(item.copyable, isTrue);

      // 剩 5 秒：快到期（門檻同 App）
      final late = _build(
        groups: [_group('g1', '我的驗證碼')],
        data: {'g1': MenuGroupData(accounts: [_account('a', 'GitHub')], secrets: _secrets({'a': _secret}))},
        now: _now + 20000,
      );
      expect(late.items.single.remaining, '5 秒');
      expect(late.items.single.expiring, isTrue);
    });

    test('載入中、沒有驗證碼、無法載入、金鑰錯誤', () {
      final model = _build(
        groups: [_group('g1', 'A'), _group('g2', 'B'), _group('g3', 'C'), _group('g4', 'D')],
        data: {
          'g2': const MenuGroupData(accounts: []),
          'g3': const MenuGroupData(error: '連不上'),
          'g4': MenuGroupData(accounts: [_account('a', 'Bad')], secrets: _secrets({'a': '!!!'})),
        },
      );
      expect(model.sections.map((s) => s.note).toList(), ['載入中', '沒有驗證碼', '無法載入', null]);
      final bad = model.items.single;
      expect(bad.code, '金鑰錯誤');
      expect(bad.copyable, isFalse);
    });

    test('沒有金鑰也還沒拿到伺服器產碼時顯示佔位，不能複製', () {
      final model = _build(
        groups: [_group('g1', 'A')],
        data: {'g1': MenuGroupData(accounts: [_account('a', 'View only')])},
      );
      expect(model.items.single.code, '--- ---');
      expect(model.items.single.copyable, isFalse);
      expect(model.codeFor('g1/a', _now), isNull);
    });

    test('驗證碼太多時每個群組收成子選單', () {
      final many = [for (var i = 0; i < menuBarInlineLimit + 1; i++) _account('a$i', 'Code $i')];
      final model = _build(
        groups: [_group('g1', 'A')],
        data: {'g1': MenuGroupData(accounts: many, secrets: _secrets({for (final a in many) a.id: _secret}))},
      );
      expect(model.submenus, isTrue);
      expect(model.toMap()['submenus'], isTrue);
    });

    test('名稱太長會截斷', () {
      final model = _build(
        groups: [_group('g1', 'A')],
        data: {'g1': MenuGroupData(accounts: [_account('a', 'x' * 80)], secrets: _secrets({'a': _secret}))},
      );
      expect(model.items.single.name.runes.length, 32);
      expect(model.items.single.name, endsWith('…'));
    });
  });

  group('一行文字（Linux 系統匣）', () {
    test('名稱、驗證碼、剩餘秒數用全形空白隔開，和欄位的內容一致', () {
      final model = _build(
        groups: [_group('g1', 'A')],
        data: {'g1': MenuGroupData(accounts: [_account('a', 'GitHub')], secrets: _secrets({'a': _secret}))},
      );
      final item = model.items.single;
      expect(item.label, 'GitHub\u3000${formatOtp(expected)}\u300025 秒');
      final map = (model.toMap()['sections'] as List).single as Map;
      expect(((map['items'] as List).single as Map)['label'], item.label);
    });

    test('快到期時秒數前加「剩」，沒有秒數時只有名稱與狀態', () {
      final data = {'g1': MenuGroupData(accounts: [_account('a', 'GitHub')], secrets: _secrets({'a': _secret}))};
      final late = _build(groups: [_group('g1', 'A')], data: data, now: _now + 20000);
      expect(late.items.single.label, endsWith('\u3000剩 5 秒'));

      final structure = _build(groups: [_group('g1', 'A')], data: data, withCodes: false);
      expect(structure.items.single.label, 'GitHub\u3000--- ---');

      final bad = _build(
        groups: [_group('g1', 'A')],
        data: {'g1': MenuGroupData(accounts: [_account('a', 'Bad')], secrets: _secrets({'a': '!!!'}))},
      );
      expect(bad.items.single.label, 'Bad\u3000金鑰錯誤');
    });

    test('隱藏驗證碼時一行文字也只有圓點', () {
      final model = _build(
        hideCodes: true,
        groups: [_group('g1', 'A')],
        data: {'g1': MenuGroupData(accounts: [_account('a', 'GitHub')], secrets: _secrets({'a': _secret}))},
      );
      expect(model.items.single.label, contains('••• •••'));
      expect(model.toMap().toString(), isNot(contains(expected)));
    });
  });

  group('遮住與複製', () {
    test('隱藏驗證碼時顯示圓點，點了一樣複製真正的碼', () {
      final model = _build(
        hideCodes: true,
        groups: [_group('g1', 'A')],
        data: {'g1': MenuGroupData(accounts: [_account('a', 'GitHub')], secrets: _secrets({'a': _secret}))},
      );
      final item = model.items.single;
      expect(item.code, '••• •••');
      expect(item.code, isNot(contains(expected.substring(0, 3))));
      expect(item.copyable, isTrue);
      expect(model.codeFor('g1/a', _now), expected);
      expect(model.codeFor('g1/missing', _now), isNull);
    });

    test('只送結構時沒有驗證碼，也不能複製', () {
      final model = _build(
        groups: [_group('g1', 'A')],
        data: {'g1': MenuGroupData(accounts: [_account('a', 'GitHub')], secrets: _secrets({'a': _secret}))},
        withCodes: false,
      );
      final item = model.items.single;
      expect(item.code, '--- ---');
      expect(item.remaining, isNull);
      expect(item.copyable, isFalse);
      expect(model.codeFor('g1/a', _now), isNull);
      expect(model.toMap().toString(), isNot(contains(expected)));
    });

    test('送到原生端的內容沒有金鑰', () {
      final model = _build(
        groups: [_group('g1', 'A')],
        data: {'g1': MenuGroupData(accounts: [_account('a', 'GitHub')], secrets: _secrets({'a': _secret}))},
      );
      expect(model.toMap().toString(), isNot(contains(_secret)));
    });
  });

  group('鎖定與登入', () {
    final groups = [_group('g1', 'A')];
    final data = {'g1': MenuGroupData(accounts: [_account('a', 'GitHub')], secrets: _secrets({'a': _secret}))};

    test('App 鎖定時不列出任何驗證碼', () {
      final model = _build(appLocked: true, groups: groups, data: data);
      expect(model.status, MenuBarStatus.locked);
      expect(model.message, '已鎖定，打開 Securibit 解鎖');
      expect(model.sections, isEmpty);
      expect(model.codeFor('g1/a', _now), isNull);
      expect(model.showSettings, isTrue);
    });

    test('沒有登入時只顯示尚未登入', () {
      final model = _build(signedIn: false, groups: groups, data: data);
      expect(model.status, MenuBarStatus.signedOut);
      expect(model.message, '尚未登入');
      expect(model.sections, isEmpty);
      expect(model.showSettings, isFalse);
    });

    test('還在載入使用者資料或群組', () {
      expect(_build(profileReady: false, groups: groups, data: data).status, MenuBarStatus.loading);
      final loading = _build();
      expect(loading.status, MenuBarStatus.loading);
      expect(loading.message, '載入中');
    });

    test('沒解鎖的加密群組顯示需要解鎖，不列出驗證碼', () {
      final vault = [_group('g1', '加密', encrypted: true)];
      final locked = _build(groups: vault, data: data);
      expect(locked.sections.single.note, '需要解鎖');
      expect(locked.items, isEmpty);
      expect(locked.codeFor('g1/a', _now), isNull);

      final unlocked = _build(groups: vault, data: data, vaultUnlocked: true);
      expect(unlocked.items.single.code, formatOtp(expected));

      // 不是擁有者（例如全站管理員）就算這台裝置解鎖了也看不到
      final other = _build(groups: [_group('g1', '加密', encrypted: true, isOwner: false)], data: data, vaultUnlocked: true);
      expect(other.sections.single.note, '需要解鎖');
    });
  });
}
