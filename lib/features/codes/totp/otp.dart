import '../../../src/rust/api/totp.dart' as core;
import 'totp_params.dart';

/*
 * TOTP（RFC 6238）的計算在 Rust 安全核心（rust/core/src/totp.rs），結果與網站用的 totp-generator 相同。
 * 群組裡的驗證碼不走這裡（金鑰留在 Rust，見 SecretHandle）；這裡給介紹頁的示範金鑰與後台用。
 * 金鑰不合法時回傳 null（畫面顯示「金鑰錯誤」）。
 */
String? generateOtp({
  required String secret,
  int digits = TotpDefaults.digits,
  int period = TotpDefaults.period,
  TotpAlgorithm algorithm = TotpDefaults.algorithm,
  required int timestampMs,
}) =>
    core.totpGenerate(secret: secret, digits: digits, period: period, algorithm: algorithm.label, timestampMs: timestampMs);

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
