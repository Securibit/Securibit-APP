import '../../../core/result.dart';
import 'categories.dart';
import 'secret.dart';
import 'totp_params.dart';

/*
 * otpauth:// 連結（Key URI Format，各服務綁定用的 QR Code 內容就是這個），同網站 src/lib/totp/otpauth.ts：
 * otpauth://totp/Issuer:account?secret=...&issuer=...&digits=6&period=30&algorithm=SHA1
 */

const _invalidLink = '不是有效的 otpauth:// 連結';

/// 組出顯示名稱：label 可能是「Issuer:account」或只有 account，issuer 參數優先。
/// 結果為「Issuer - account」，只有其中一個就用那個
String composeName(String label, [String issuerParam = '']) {
  final separator = label.indexOf(':');
  final labelIssuer = separator >= 0 ? label.substring(0, separator).trim() : '';
  final account = (separator >= 0 ? label.substring(separator + 1) : label).trim();
  final issuer = issuerParam.trim().isNotEmpty ? issuerParam.trim() : labelIssuer;

  if (issuer.isNotEmpty && account.isNotEmpty && issuer != account) return '$issuer - $account';
  if (issuer.isNotEmpty) return issuer;
  if (account.isNotEmpty) return account;
  return '未命名';
}

// otpauth 的 algorithm 參數寫作 SHA1 / SHA256 / SHA512
TotpAlgorithm? _toAlgorithm(String? value) {
  if (value == null || value.isEmpty) return TotpDefaults.algorithm;
  final normalized = value.toUpperCase().replaceFirst(RegExp(r'^SHA-?'), 'SHA-');
  for (final algorithm in TotpAlgorithm.values) {
    if (algorithm.label == normalized) return algorithm;
  }
  return null;
}

// 同一個參數出現多次時取第一個（同瀏覽器的 URLSearchParams.get）
String? _param(Uri uri, String key) {
  final values = uri.queryParametersAll[key];
  return values == null || values.isEmpty ? null : values.first;
}

// 同 JS 的 Number()：沒有參數用預設值、空字串是 0、不是數字為 null
num? _toNumber(String? value, int fallback) {
  if (value == null) return fallback;
  final trimmed = value.trim();
  return trimmed.isEmpty ? 0 : num.tryParse(trimmed);
}

Result<TotpInput> parseOtpauthUri(String text) {
  final raw = text.trim();
  Uri uri;
  try {
    uri = Uri.parse(raw);
  } on FormatException {
    return const Err(_invalidLink);
  }

  if (uri.scheme.toLowerCase() != 'otpauth') return const Err(_invalidLink);
  final type = uri.host.toLowerCase();
  if (type == 'hotp') return const Err('目前只支援 TOTP（時間型）驗證碼，不支援 HOTP（計數型）');
  if (type != 'totp') return const Err(_invalidLink);

  String secret;
  try {
    secret = normalizeSecret(_param(uri, 'secret') ?? '');
  } on FormatException {
    return const Err(_invalidLink);
  }
  if (secret.isEmpty) return const Err('連結裡沒有金鑰（secret）');
  if (!isValidSecret(secret)) return const Err('連結裡的金鑰不是 Base32 格式');

  final digitsText = _param(uri, 'digits');
  final digits = _toNumber(digitsText, TotpDefaults.digits);
  if (digits == null || !totpDigitsOptions.contains(digits)) return Err('不支援 ${digitsText?.trim()} 位數的驗證碼');

  final periodText = _param(uri, 'period');
  final period = _toNumber(periodText, TotpDefaults.period);
  if (period == null || !totpPeriodOptions.contains(period)) return Err('不支援 ${periodText?.trim()} 秒的週期');

  final algorithmText = _param(uri, 'algorithm');
  final algorithm = _toAlgorithm(algorithmText);
  if (algorithm == null) return Err('不支援 $algorithmText 演算法');

  String label;
  try {
    label = Uri.decodeComponent(uri.path.replaceFirst(RegExp(r'^/'), '')).trim();
  } on ArgumentError {
    label = uri.path.replaceFirst(RegExp(r'^/'), '').trim();
  }
  final name = composeName(label, _param(uri, 'issuer') ?? '');
  // category 不是標準參數，是網站匯出備份時加上的（多個類別用「,」串起來），其他 App 會忽略
  final category = normalizeCategories(_param(uri, 'category'));

  return Ok(TotpInput(
    name: name,
    secret: secret,
    category: category,
    digits: digits.toInt(),
    period: period.toInt(),
    algorithm: algorithm,
  ));
}

/// 產生 otpauth:// 連結（可轉成 QR Code 給其他驗證器 App 掃）
String buildOtpauthUri(TotpInput item) {
  final query = <String, String>{
    'secret': normalizeSecret(item.secret),
    'algorithm': item.algorithm.label.replaceAll('-', ''),
    'digits': '${item.digits}',
    'period': '${item.period}',
    if (item.category.isNotEmpty) 'category': item.category,
  };
  final encoded = query.entries.map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}').join('&');
  return 'otpauth://totp/${Uri.encodeComponent(item.name)}?$encoded';
}
