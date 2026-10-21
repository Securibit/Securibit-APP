import 'package:flutter_test/flutter_test.dart';
import 'package:securibit/core/result.dart';
import 'package:securibit/features/codes/totp/categories.dart';
import 'package:securibit/features/codes/totp/otpauth.dart';
import 'package:securibit/features/codes/totp/totp_params.dart';

TotpInput ok(String uri) => switch (parseOtpauthUri(uri)) {
      Ok(:final data) => data,
      Err(:final message) => throw StateError(message),
    };

String err(String uri) => parseOtpauthUri(uri).messageOrNull ?? 'ok';

void main() {
  test('標準連結', () {
    final item = ok('otpauth://totp/GitHub:me%40example.com?secret=jbswy3dpehpk3pxp&issuer=GitHub');
    expect(item.name, 'GitHub - me@example.com');
    expect(item.secret, 'JBSWY3DPEHPK3PXP');
    expect(item.digits, 6);
    expect(item.period, 30);
    expect(item.algorithm, TotpAlgorithm.sha1);
    expect(item.category, '');
  });

  test('進階參數與網站的類別參數', () {
    final item = ok(
      'otpauth://totp/Acme?secret=JBSWY3DPEHPK3PXP&digits=8&period=60&algorithm=SHA512&category=%E5%B7%A5%E4%BD%9C%EF%BC%8C%E5%80%8B%E4%BA%BA,%E5%B7%A5%E4%BD%9C',
    );
    expect(item.name, 'Acme');
    expect(item.digits, 8);
    expect(item.period, 60);
    expect(item.algorithm, TotpAlgorithm.sha512);
    expect(item.category, '工作,個人');
  });

  test('issuer 參數優先於 label', () {
    expect(ok('otpauth://totp/Old:alice?secret=JBSWY3DP&issuer=New').name, 'New - alice');
    expect(ok('otpauth://totp/alice?secret=JBSWY3DP').name, 'alice');
    expect(ok('otpauth://totp/?secret=JBSWY3DP').name, '未命名');
    expect(ok('otpauth://totp/Same:Same?secret=JBSWY3DP').name, 'Same');
    expect(ok('otpauth://totp/My%20Bank:alice?secret=JBSWY3DP').name, 'My Bank - alice');
  });

  test('錯誤訊息同網站', () {
    expect(err('https://example.com'), '不是有效的 otpauth:// 連結');
    expect(err('hello'), '不是有效的 otpauth:// 連結');
    expect(err('otpauth://hotp/a?secret=JBSWY3DP'), '目前只支援 TOTP（時間型）驗證碼，不支援 HOTP（計數型）');
    expect(err('otpauth://totp/a'), '連結裡沒有金鑰（secret）');
    expect(err('otpauth://totp/a?secret=abc1'), '連結裡的金鑰不是 Base32 格式');
    expect(err('otpauth://totp/a?secret=JBSWY3DP&digits=7'), '不支援 7 位數的驗證碼');
    expect(err('otpauth://totp/a?secret=JBSWY3DP&period=45'), '不支援 45 秒的週期');
    expect(err('otpauth://totp/a?secret=JBSWY3DP&algorithm=MD5'), '不支援 MD5 演算法');
  });

  test('產生連結再解析回來', () {
    const item = TotpInput(
      name: 'A B',
      secret: 'JBSWY3DPEHPK3PXP',
      category: '工作',
      digits: 8,
      period: 60,
      algorithm: TotpAlgorithm.sha256,
    );
    final parsed = ok(buildOtpauthUri(item));
    expect(parsed.name, 'A B');
    expect(parsed.digits, 8);
    expect(parsed.period, 60);
    expect(parsed.algorithm, TotpAlgorithm.sha256);
    expect(parsed.category, '工作');
  });

  test('多個類別', () {
    expect(parseCategories(' 工作，個人、 工作 ,'), ['工作', '個人']);
    expect(normalizeCategories('b, a ,b'), 'b,a');
    expect(collectCategories(['b,a', 'c', '']), ['a', 'b', 'c']);
    expect(formatCategories('工作,個人'), '工作、個人');
    expect(hasCategory('工作,個人', '個人'), isTrue);
  });
}
