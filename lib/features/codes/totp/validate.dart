import '../../../src/rust/api/totp.dart' as core;
import 'totp_params.dart';

// 表單錯誤（同網站 src/lib/totp/validate.ts），檢查與訊息在 Rust 安全核心（rust/core/src/validate.rs）
class TotpErrors {
  const TotpErrors({this.name, this.secret});

  final String? name;
  final String? secret;

  bool get isEmpty => name == null && secret == null;

  factory TotpErrors._from(core.TotpFieldErrors errors) => TotpErrors(name: errors.name, secret: errors.secret);
}

/// 「金鑰格式錯誤，只能包含 A-Z 與 2-7（Base32）」
final String secretFormatMessage = core.secretFormatMessage();

/// 名稱與金鑰必填、金鑰需為 Base32
TotpErrors validateTotpInput(TotpInput input) =>
    TotpErrors._from(core.validateTotpInput(name: input.name, secret: input.secret));

/// 編輯時：看不到原本金鑰的人可以留空（代表不修改），看得到的人不能清空（同網站 GroupCodeEditModal）
TotpErrors validateTotpEdit(TotpInput input, {required bool secretKnown}) =>
    TotpErrors._from(core.validateTotpEdit(name: input.name, secret: input.secret, secretKnown: secretKnown));
