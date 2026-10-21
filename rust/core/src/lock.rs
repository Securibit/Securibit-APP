/*
 * App 鎖定的圖形與密碼不存原文，只存加鹽的 PBKDF2-SHA256 雜湊（32 位元組）。
 * 四位數密碼只有一萬種組合，次數再多也擋不住離線暴力破解，
 * 真正的保護是系統的安全儲存加上 App 裡的錯誤等待，所以次數取適中（2 萬次）讓解鎖不用等。
 * 存的格式（salt、iterations、hash）和改用 Rust 之前的 Dart 版相同，舊的雜湊照樣驗證得過。
 */

use sha2::Sha256;
use subtle::ConstantTimeEq;
use zeroize::Zeroizing;

pub const ITERATIONS: u32 = 20_000;
pub const SALT_LENGTH: usize = 16;
const HASH_LENGTH: usize = 32;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct LockHash {
    pub salt: Vec<u8>,
    pub iterations: u32,
    pub hash: Vec<u8>,
}

fn derive(secret: &str, salt: &[u8], iterations: u32) -> Zeroizing<[u8; HASH_LENGTH]> {
    let mut out = Zeroizing::new([0u8; HASH_LENGTH]);
    pbkdf2::pbkdf2_hmac::<Sha256>(secret.as_bytes(), salt, iterations.max(1), out.as_mut());
    out
}

/// 產生新的鹽並雜湊圖形或密碼
pub fn hash(secret: &str, iterations: u32) -> LockHash {
    let mut salt = vec![0u8; SALT_LENGTH];
    getrandom::getrandom(&mut salt).expect("系統亂數無法使用");
    let hash = derive(secret, &salt, iterations).to_vec();
    LockHash { salt, iterations, hash }
}

/// 檢查輸入的圖形或密碼和存的雜湊是否相同（固定時間比對）
pub fn verify(secret: &str, stored: &LockHash) -> bool {
    let hash = derive(secret, &stored.salt, stored.iterations);
    constant_time_eq(hash.as_ref(), &stored.hash)
}

/// 固定時間比對：不管哪一個位元組不同，花的時間都一樣（長度不同直接是 false）
pub fn constant_time_eq(a: &[u8], b: &[u8]) -> bool {
    a.ct_eq(b).into()
}

#[cfg(test)]
mod tests {
    use super::*;
    use base64::engine::general_purpose::STANDARD;
    use base64::Engine;

    #[test]
    fn right_and_wrong() {
        let stored = hash("482913", 1000);
        assert_eq!(stored.salt.len(), 16);
        assert_eq!(stored.hash.len(), 32);
        assert!(verify("482913", &stored));
        assert!(!verify("482914", &stored));
        assert!(!verify("", &stored));
        let again = hash("482913", 1000);
        assert_ne!(stored.salt, again.salt);
        assert_ne!(stored.hash, again.hash);
    }

    // 改用 Rust 之前由 Dart（cryptography 套件）存的雜湊，換成 Rust 後還要驗證得過
    #[test]
    fn verifies_hash_made_by_old_dart_code() {
        let stored = LockHash {
            salt: STANDARD.decode(DART_SALT).unwrap(),
            iterations: ITERATIONS,
            hash: STANDARD.decode(DART_HASH).unwrap(),
        };
        assert!(verify("0-1-2-5-8", &stored));
        assert!(!verify("0-1-2-5", &stored));
    }

    pub const DART_SALT: &str = "AAECAwQFBgcICQoLDA0ODw==";
    pub const DART_HASH: &str = "FozAQs62Zp557/j6l1/R4t34NJaUf+6TBX7cI7akphQ=";

    #[test]
    fn constant_time() {
        assert!(constant_time_eq(&[1, 2, 3], &[1, 2, 3]));
        assert!(!constant_time_eq(&[1, 2, 3], &[1, 2, 4]));
        assert!(!constant_time_eq(&[1, 2, 3], &[1, 2]));
        assert!(constant_time_eq(&[], &[]));
    }
}
