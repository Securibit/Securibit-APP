import 'package:crypto/crypto.dart';

import 'base32.dart';
import 'secret.dart';
import 'totp_params.dart';

/*
 * TOTP（RFC 6238）：counter = floor(時間 / 週期)，HMAC 後做動態截斷取 digits 位數。
 * 結果與網站用的 totp-generator 相同；金鑰不合法時回傳 null（畫面顯示「金鑰錯誤」）。
 */
String? generateOtp({
  required String secret,
  int digits = TotpDefaults.digits,
  int period = TotpDefaults.period,
  TotpAlgorithm algorithm = TotpDefaults.algorithm,
  required int timestampMs,
}) {
  final normalized = normalizeSecret(secret);
  if (!isBase32(normalized)) return null;
  try {
    return hotp(base32Decode(normalized), timestampMs ~/ 1000 ~/ period, digits: digits, algorithm: algorithm);
  } on FormatException {
    return null;
  }
}

/// HOTP（RFC 4226）：key 是原始金鑰位元組
String hotp(List<int> key, int counter, {int digits = TotpDefaults.digits, TotpAlgorithm algorithm = TotpDefaults.algorithm}) {
  final message = List<int>.filled(8, 0);
  var value = counter;
  for (var i = 7; i >= 0; i--) {
    message[i] = value & 0xff;
    value >>= 8;
  }
  final hash = switch (algorithm) {
    TotpAlgorithm.sha1 => sha1,
    TotpAlgorithm.sha256 => sha256,
    TotpAlgorithm.sha512 => sha512,
  };
  final mac = Hmac(hash, key).convert(message).bytes;
  final offset = mac.last & 0x0f;
  final binary = ((mac[offset] & 0x7f) << 24) |
      ((mac[offset + 1] & 0xff) << 16) |
      ((mac[offset + 2] & 0xff) << 8) |
      (mac[offset + 3] & 0xff);
  var modulo = 1;
  for (var i = 0; i < digits; i++) {
    modulo *= 10;
  }
  return (binary % modulo).toString().padLeft(digits, '0');
}

/// 每 3 / 4 位插一個空白方便閱讀（6 位數 → 123 456，8 位數 → 1234 5678），同網站
String formatOtp(String otp) {
  if (otp.length == 6) return '${otp.substring(0, 3)} ${otp.substring(3)}';
  final buffer = StringBuffer();
  for (var i = 0; i < otp.length; i++) {
    if (i > 0 && i % 4 == 0) buffer.write(' ');
    buffer.write(otp[i]);
  }
  return buffer.toString();
}

/// 快到期（變紅、顯示下一組）的門檻，同網站 GroupCodeCard：剩餘 ≤ min(10, 週期 / 3) 秒
bool isExpiring(int secondsLeft, int period) => secondsLeft <= (period / 3 < 10 ? period / 3 : 10);
