import '../code_models.dart';
import '../codes_controller.dart';
import '../totp/otpauth.dart';
import '../totp/totp_params.dart';

/*
 * 匯出的資料（同網站 ExportModal）：只有我有「查看金鑰」、金鑰也解得開的項目能匯出。
 * 金鑰在 Rust，按下匯出時才用 SecretHandle.reveal 取出來組成連結。
 */

/// 一筆驗證碼加上金鑰，組成可以產生連結的內容
TotpInput exportInput(GroupAccount account, String secret) => TotpInput(
      name: account.name,
      secret: secret,
      category: account.category,
      digits: account.digits,
      period: account.period,
      algorithm: account.algorithm,
    );

/// 可以匯出的項目（依清單順序）與不能匯出的筆數（沒有「查看金鑰」或金鑰錯誤）
({List<TotpInput> items, int missing}) exportableItems(CodesController controller) {
  final items = <TotpInput>[];
  var missing = 0;
  for (final account in controller.ordered) {
    final handle = controller.secretOf(account);
    final secret = handle != null && handle.valid ? handle.reveal() : null;
    if (secret == null || secret.isEmpty) {
      missing++;
    } else {
      items.add(exportInput(account, secret));
    }
  }
  return (items: items, missing: missing);
}

String _two(int value) => value.toString().padLeft(2, '0');

/// 備份檔的檔名：securibit-totp-20261021.txt
String backupFileName(DateTime now) => 'securibit-totp-${now.year}${_two(now.month)}${_two(now.day)}.txt';

/// 文字備份：兩行註解，接著每行一個 otpauth 連結（含類別），可以再整批匯入
String buildBackupText(List<TotpInput> items, DateTime now) {
  final time = '${now.year}/${_two(now.month)}/${_two(now.day)} ${_two(now.hour)}:${_two(now.minute)}';
  return [
    '# Securibit TOTP 備份（$time，共 ${items.length} 筆）',
    '# 每行一個 otpauth:// 連結，可匯入本站或其他支援的驗證器 App',
    ...items.map(buildOtpauthUri),
  ].join('\n');
}
