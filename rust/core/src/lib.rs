/*!
 * Securibit 的安全核心（純 Rust，不依賴 flutter_rust_bridge）。
 * App 的 Dart 端只透過 rust/api 呼叫這裡；金鑰、加密群組的金鑰都留在這個 crate 的記憶體裡，用完歸零。
 *
 * - base32 / secret / validate：金鑰格式（同網站 src/lib/totp）
 * - totp：TOTP / HOTP（RFC 6238 / 4226）
 * - otpauth：otpauth:// 連結
 * - vault：加密群組 enc:v1（PBKDF2-SHA256 60 萬次 → AES-GCM 256，與網站 src/lib/vault/crypto.ts 逐位元組相容）
 * - lock：App 鎖定的圖形 / 密碼雜湊（PBKDF2-SHA256 2 萬次，固定時間比對）
 * - sealed：用這台裝置的金鑰把離線快取的金鑰封起來
 * - rpc_body：送給伺服器、含金鑰的 JSON（寫在會歸零的緩衝區）
 * - store：記憶體裡的金鑰保管（依群組、驗證碼 id），只回傳驗證碼
 * - qr_image：從圖片讀 QR Code（Linux 沒有系統內建的辨識時用）
 */

pub mod base32;
pub mod lock;
pub mod otpauth;
pub mod qr_image;
pub mod rpc_body;
pub mod sealed;
pub mod secret;
pub mod store;
pub mod totp;
pub mod validate;
pub mod vault;

mod b64;
