import 'secret.dart';
import 'totp_params.dart';

// 表單錯誤（同網站 src/lib/totp/validate.ts）
class TotpErrors {
  const TotpErrors({this.name, this.secret});

  final String? name;
  final String? secret;

  bool get isEmpty => name == null && secret == null;
}

const secretFormatMessage = '金鑰格式錯誤，只能包含 A-Z 與 2-7（Base32）';

/// 名稱與金鑰必填、金鑰需為 Base32
TotpErrors validateTotpInput(TotpInput input) {
  String? name;
  String? secret;
  if (input.name.trim().isEmpty) name = '請輸入名稱';
  if (normalizeSecret(input.secret).isEmpty) {
    secret = '請輸入金鑰';
  } else if (!isValidSecret(input.secret)) {
    secret = secretFormatMessage;
  }
  return TotpErrors(name: name, secret: secret);
}

/// 編輯時：看不到原本金鑰的人可以留空（代表不修改），看得到的人不能清空（同網站 GroupCodeEditModal）
TotpErrors validateTotpEdit(TotpInput input, {required bool secretKnown}) {
  String? name;
  String? secret;
  if (input.name.trim().isEmpty) name = '請輸入名稱';
  if (normalizeSecret(input.secret).isEmpty) {
    if (secretKnown) secret = '請輸入金鑰';
  } else if (!isValidSecret(input.secret)) {
    secret = secretFormatMessage;
  }
  return TotpErrors(name: name, secret: secret);
}
