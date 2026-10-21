// 金鑰的正規化與檢查（同網站 src/lib/totp/crud.ts）

/// 去除空白與連字號、轉大寫、去掉結尾的 = 補位（許多金鑰是小寫或分組顯示）
String normalizeSecret(String secret) =>
    secret.replaceAll(RegExp(r'[\s-]'), '').toUpperCase().replaceAll(RegExp(r'=+$'), '');

final _base32Pattern = RegExp(r'^[A-Z2-7]+=*$');

bool isBase32(String input) => _base32Pattern.hasMatch(input);

/// 金鑰是否可用（正規化後為 Base32）
bool isValidSecret(String secret) => isBase32(normalizeSecret(secret));
