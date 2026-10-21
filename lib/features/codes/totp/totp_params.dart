// 驗證碼的參數（與網站 src/types/Totp/Totp.ts 相同的選項與預設值）

enum TotpAlgorithm {
  sha1('SHA-1'),
  sha256('SHA-256'),
  sha512('SHA-512');

  const TotpAlgorithm(this.label);

  // 資料庫與畫面上的寫法：SHA-1 / SHA-256 / SHA-512
  final String label;

  static TotpAlgorithm fromLabel(String? value) =>
      TotpAlgorithm.values.firstWhere((a) => a.label == value, orElse: () => TotpDefaults.algorithm);
}

class TotpDefaults {
  TotpDefaults._();

  // 與 Google Authenticator 相同
  static const digits = 6;
  static const period = 30;
  static const algorithm = TotpAlgorithm.sha1;
}

const totpDigitsOptions = [6, 8];
const totpPeriodOptions = [30, 60];

/// 新增 / 編輯表單送出的內容
class TotpInput {
  const TotpInput({
    required this.name,
    required this.secret,
    this.category = '',
    this.digits = TotpDefaults.digits,
    this.period = TotpDefaults.period,
    this.algorithm = TotpDefaults.algorithm,
  });

  static const empty = TotpInput(name: '', secret: '');

  final String name;
  final String secret;
  // 多個類別用「,」串起來（見 categories.dart）
  final String category;
  final int digits;
  final int period;
  final TotpAlgorithm algorithm;

  bool get isDefaultAdvanced =>
      digits == TotpDefaults.digits && period == TotpDefaults.period && algorithm == TotpDefaults.algorithm;

  TotpInput copyWith({String? name, String? secret, String? category, int? digits, int? period, TotpAlgorithm? algorithm}) =>
      TotpInput(
        name: name ?? this.name,
        secret: secret ?? this.secret,
        category: category ?? this.category,
        digits: digits ?? this.digits,
        period: period ?? this.period,
        algorithm: algorithm ?? this.algorithm,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'secret': secret,
        'category': category,
        'digits': digits,
        'period': period,
        'algorithm': algorithm.label,
      };
}
