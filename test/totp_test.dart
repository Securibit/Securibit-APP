import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:securibit/features/codes/totp/otp.dart';
import 'package:securibit/features/codes/totp/totp_params.dart';
import 'package:securibit/src/rust/api/totp.dart' as core;

// TOTP 的計算在 Rust 安全核心，這裡從 Dart 端呼叫確認結果
void main() {
  // RFC 6238 附錄 B 的測試向量（8 位數、30 秒）；三種演算法的金鑰長度不同
  group('RFC 6238', () {
    final keys = {
      TotpAlgorithm.sha1: '12345678901234567890',
      TotpAlgorithm.sha256: '12345678901234567890123456789012',
      TotpAlgorithm.sha512: '1234567890123456789012345678901234567890123456789012345678901234',
    };
    const vectors = <int, Map<TotpAlgorithm, String>>{
      59: {TotpAlgorithm.sha1: '94287082', TotpAlgorithm.sha256: '46119246', TotpAlgorithm.sha512: '90693936'},
      1111111109: {TotpAlgorithm.sha1: '07081804', TotpAlgorithm.sha256: '68084774', TotpAlgorithm.sha512: '25091201'},
      1111111111: {TotpAlgorithm.sha1: '14050471', TotpAlgorithm.sha256: '67062674', TotpAlgorithm.sha512: '99943326'},
      1234567890: {TotpAlgorithm.sha1: '89005924', TotpAlgorithm.sha256: '91819424', TotpAlgorithm.sha512: '93441116'},
      2000000000: {TotpAlgorithm.sha1: '69279037', TotpAlgorithm.sha256: '90698825', TotpAlgorithm.sha512: '38618901'},
      20000000000: {TotpAlgorithm.sha1: '65353130', TotpAlgorithm.sha256: '77737706', TotpAlgorithm.sha512: '47863826'},
    };

    vectors.forEach((time, expected) {
      expected.forEach((algorithm, code) {
        test('${algorithm.label} @ $time', () {
          final secret = core.base32Encode(bytes: ascii.encode(keys[algorithm]!));
          expect(
            generateOtp(secret: secret, digits: 8, period: 30, algorithm: algorithm, timestampMs: time * 1000),
            code,
          );
        });
      });
    });
  });

  // 用網站實際使用的 totp-generator（node）產生的結果比對
  test('與網站 totp-generator 相同', () {
    expect(generateOtp(secret: 'JBSWY3DPEHPK3PXP', timestampMs: 1700000000000), '324550');
    expect(
      generateOtp(
        secret: 'jbsw y3dp ehpk 3pxp',
        digits: 8,
        period: 60,
        algorithm: TotpAlgorithm.sha256,
        timestampMs: 1700000000000,
      ),
      '71205722',
    );
    expect(
      generateOtp(
        secret: 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ',
        digits: 8,
        algorithm: TotpAlgorithm.sha512,
        timestampMs: 1234567890000,
      ),
      '76671578',
    );
  });

  test('金鑰不合法時回傳 null', () {
    expect(generateOtp(secret: 'not base32!', timestampMs: 0), isNull);
    expect(generateOtp(secret: '', timestampMs: 0), isNull);
  });

  test('顯示格式與到期門檻', () {
    expect(formatOtp('123456'), '123 456');
    expect(formatOtp('12345678'), '1234 5678');
    expect(isExpiring(10, 30), isTrue);
    expect(isExpiring(11, 30), isFalse);
    expect(isExpiring(10, 60), isTrue);
    expect(isExpiring(11, 60), isFalse);
  });
}
