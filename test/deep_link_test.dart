import 'package:flutter_test/flutter_test.dart';
import 'package:securibit/core/permissions.dart';
import 'package:securibit/features/codes/totp/migration.dart';
import 'package:securibit/features/codes/totp/otpauth.dart';
import 'package:securibit/features/codes/totp/totp_params.dart';
import 'package:securibit/features/groups/group_models.dart';
import 'package:securibit/features/links/deep_link.dart';
import 'package:securibit/features/links/deep_link_controller.dart';

/*
 * 點連結打開 App：連結的解析、對應到哪個動作，以及還沒登入、鎖定時先留著（見 lib/features/links/）
 */

const _web = 'https://2fa.bityo.tw';
const _code = 'AbC123_-xyz';

const _item = TotpInput(name: 'GitHub:me@example.com', secret: 'JBSWY3DPEHPK3PXP', category: '');

GroupSummary _group(String id, {int permissions = GroupPermission.manageCodes, bool encrypted = false, bool isOwner = true}) => GroupSummary(
      id: id,
      name: id,
      description: '',
      ownerId: 'owner',
      isOwner: isOwner,
      isDefault: false,
      encrypted: encrypted,
      position: 0,
      memberCount: 1,
      accountCount: 0,
      permissions: permissions,
    );

void main() {
  group('邀請連結', () {
    test('網站的 /invite/<code>（可帶查詢字串、結尾斜線）', () {
      expect(parseDeepLink('$_web/invite/$_code', webUrl: _web), const InviteLink(_code));
      expect(parseDeepLink('$_web/invite/$_code?from=line#x', webUrl: _web), const InviteLink(_code));
      expect(parseDeepLink('$_web/invite/$_code/', webUrl: _web), const InviteLink(_code));
      expect(parseDeepLink('  https://2FA.bityo.tw/invite/$_code  ', webUrl: _web), const InviteLink(_code));
    });

    test('env.json 設定的網站網址也接受', () {
      const self = 'https://2fa.example.com';
      expect(parseDeepLink('$self/invite/$_code', webUrl: self), const InviteLink(_code));
      // 正式站一直都接受（Android 的 App Links 只認它）
      expect(parseDeepLink('$_web/invite/$_code', webUrl: self), const InviteLink(_code));
    });

    test('securibit://invite/<code>（桌面版）', () {
      expect(parseDeepLink('securibit://invite/$_code'), const InviteLink(_code));
      expect(parseDeepLink('SECURIBIT://invite/$_code'), const InviteLink(_code));
    });

    test('代碼格式不對', () {
      for (final link in ['securibit://invite/', 'securibit://invite/abc', '$_web/invite/有中文的代碼', '$_web/invite/']) {
        final result = parseDeepLink(link, webUrl: _web);
        expect(result, isA<InvalidLink>(), reason: link);
        expect((result as InvalidLink).title, '無法開啟邀請連結');
      }
    });

    test('其他網站或其他路徑不是邀請', () {
      expect(parseDeepLink('https://evil.example.com/invite/$_code', webUrl: _web), isA<InvalidLink>());
      expect(parseDeepLink('$_web/download', webUrl: _web), isA<InvalidLink>());
      expect(parseDeepLink('securibit://groups/$_code'), isA<InvalidLink>());
    });
  });

  group('驗證碼連結', () {
    test('otpauth:// 開新增表單，帶原本的連結', () {
      final link = buildOtpauthUri(_item);
      expect(parseDeepLink(link), CodeLink(link, bulk: false));
    });

    test('otpauth-migration:// 開整批匯入', () {
      final link = buildMigrationUris([_item, const TotpInput(name: 'AWS', secret: 'GEZDGNBVGY3TQOJQ', category: '')]).single;
      expect(parseDeepLink(link), CodeLink(link, bulk: true));
    });

    test('格式不對時是中文錯誤', () {
      final missingSecret = parseDeepLink('otpauth://totp/GitHub?issuer=GitHub');
      expect(missingSecret, isA<InvalidLink>());
      expect((missingSecret as InvalidLink).title, '無法新增驗證碼');
      expect(missingSecret.message, isNotEmpty);

      final broken = parseDeepLink('otpauth-migration://offline?data=%%%');
      expect(broken, isA<InvalidLink>());
      expect((broken as InvalidLink).title, '無法匯入驗證碼');
    });
  });

  group('其他連結', () {
    test('Google 登入轉回來的連結交給 supabase，不處理', () {
      expect(parseDeepLink('securibit://login-callback?code=abc'), isNull);
      expect(parseDeepLink('   '), isNull);
    });

    test('不認得的連結', () {
      final result = parseDeepLink('mailto:me@example.com');
      expect(result, isA<InvalidLink>());
      expect((result as InvalidLink).title, '無法開啟這個連結');
    });
  });

  group('排隊', () {
    late DateTime now;
    late DeepLinkController links;

    setUp(() {
      now = DateTime(2026, 10, 22, 12);
      links = DeepLinkController(webUrl: _web, clock: () => now);
    });

    test('還沒登入時留著，登入後才取出', () {
      links.receive('$_web/invite/$_code');
      expect(links.takeIfReady(signedIn: false, locked: false), isNull);
      expect(links.pending, const InviteLink(_code));
      expect(links.takeIfReady(signedIn: true, locked: false), const InviteLink(_code));
      expect(links.pending, isNull);
      expect(links.takeIfReady(signedIn: true, locked: false), isNull);
    });

    test('鎖定中留著，解鎖後才取出', () {
      links.receive('securibit://invite/$_code');
      expect(links.takeIfReady(signedIn: true, locked: true), isNull);
      expect(links.takeIfReady(signedIn: true, locked: false), const InviteLink(_code));
    });

    test('只留最新的一個；登入轉回來的連結不會蓋掉', () {
      final otp = buildOtpauthUri(_item);
      links.receive('securibit://invite/$_code');
      links.receive(otp);
      links.receive('securibit://login-callback?code=abc');
      expect(links.takeIfReady(signedIn: true, locked: false), CodeLink(otp, bulk: false));
    });

    test('格式不對的不排隊', () {
      var notified = 0;
      links.addListener(() => notified++);
      expect(links.receive('securibit://invite/x'), isA<InvalidLink>());
      expect(links.pending, isNull);
      expect(notified, 0);
    });

    test('初始連結與串流各給一次時只算一次，過一陣子再點就再算', () {
      expect(links.accept('securibit://invite/$_code'), const InviteLink(_code));
      expect(links.accept('securibit://invite/$_code'), isNull);
      now = now.add(DeepLinkController.duplicateWindow);
      expect(links.accept('securibit://invite/$_code'), const InviteLink(_code));
    });

    test('選好群組後只交給那個群組', () {
      links.requestCode('g2', 'otpauth://totp/x?secret=JBSWY3DPEHPK3PXP');
      expect(links.takeCodeRequest('g1'), isNull);
      final request = links.takeCodeRequest('g2');
      expect(request?.text, 'otpauth://totp/x?secret=JBSWY3DPEHPK3PXP');
      expect(links.takeCodeRequest('g2'), isNull);
    });
  });

  group('可以新增驗證碼的群組', () {
    test('要有管理驗證碼；加密的群組要擁有者而且已解鎖', () {
      final groups = [
        _group('ok'),
        _group('view', permissions: GroupPermission.viewCodes),
        _group('vault', encrypted: true),
        _group('other-vault', encrypted: true, isOwner: false),
      ];
      expect(groupsForNewCode(groups, vaultUnlocked: false).map((g) => g.id), ['ok']);
      expect(groupsForNewCode(groups, vaultUnlocked: true).map((g) => g.id), ['ok', 'vault']);
    });

    test('沒有可以新增的群組時說明原因', () {
      expect(noGroupForNewCodeReason([_group('vault', encrypted: true)]), contains('解鎖'));
      expect(noGroupForNewCodeReason([_group('view', permissions: 0)]), contains('管理驗證碼'));
    });
  });
}
