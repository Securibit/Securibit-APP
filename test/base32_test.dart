import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:securibit/features/codes/totp/secret.dart';
import 'package:securibit/features/codes/totp/totp_params.dart';
import 'package:securibit/features/codes/totp/validate.dart';
import 'package:securibit/src/rust/api/totp.dart' as core;

// Base32、金鑰檢查與表單驗證都在 Rust 安全核心，這裡確認 Dart 端拿到的結果與訊息同網站
void main() {
  test('RFC 4648 編碼（不補 =）', () {
    expect(core.base32Encode(bytes: ascii.encode('')), '');
    expect(core.base32Encode(bytes: ascii.encode('f')), 'MY');
    expect(core.base32Encode(bytes: ascii.encode('foobar')), 'MZXW6YTBOI');
    expect(utf8.decode(core.base32Decode(input: 'MZXW6YTBOI').bytes), 'foobar');
    expect(core.base32Decode(input: 'MZ1').error, '不是 Base32 字元：1');
  });

  test('正規化：去空白、連字號、轉大寫、去掉結尾的 =', () {
    expect(normalizeSecret(' jbsw-y3dp ehpk 3pxp=='), 'JBSWY3DPEHPK3PXP');
  });

  test('Base32 檢查', () {
    expect(isValidSecret('JBSWY3DPEHPK3PXP'), isTrue);
    expect(isValidSecret('jbsw y3dp'), isTrue);
    expect(isValidSecret('JBSWY3DPEHPK3PX1'), isFalse);
    expect(isValidSecret('JBSWY3DP0'), isFalse);
    expect(isValidSecret(''), isFalse);
  });

  test('表單驗證的訊息同網站', () {
    final empty = validateTotpInput(TotpInput.empty);
    expect(empty.name, '請輸入名稱');
    expect(empty.secret, '請輸入金鑰');

    final bad = validateTotpInput(const TotpInput(name: 'a', secret: 'abc1'));
    expect(bad.name, isNull);
    expect(bad.secret, secretFormatMessage);
    expect(secretFormatMessage, '金鑰格式錯誤，只能包含 A-Z 與 2-7（Base32）');

    expect(validateTotpInput(const TotpInput(name: 'a', secret: 'jbsw y3dp')).isEmpty, isTrue);

    // 編輯：看不到金鑰時留空代表不修改
    expect(validateTotpEdit(const TotpInput(name: 'a', secret: ''), secretKnown: false).isEmpty, isTrue);
    expect(validateTotpEdit(const TotpInput(name: 'a', secret: ''), secretKnown: true).secret, '請輸入金鑰');
  });
}
