import '../../../src/rust/api/totp.dart' as core;

// 金鑰的正規化與檢查（同網站 src/lib/totp/crud.ts），實作在 Rust 安全核心（rust/core/src/secret.rs）

/// 去除空白與連字號、轉大寫、去掉結尾的 = 補位（許多金鑰是小寫或分組顯示）
String normalizeSecret(String secret) => core.normalizeSecret(secret: secret);

/// 金鑰是否可用（正規化後為 Base32）
bool isValidSecret(String secret) => core.isValidSecret(secret: secret);
