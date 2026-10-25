/*
 * 加密群組的金鑰加密，與網站 src/lib/vault/crypto.ts 逐位元組相容：
 * 使用者密碼（UTF-8）→ PBKDF2-SHA256（600,000 次）→ AES-GCM 256。
 * 密文格式 enc:v1:<iv base64>:<密文＋16 位元組 tag base64>，iv 12 位元組。
 * 解開的金鑰只放在 VaultKey 裡，離開作用域時自動歸零。
 *
 * 設定、更改、停用密碼與開關群組加密時，整批金鑰的重新加密也在這裡（同網站 VaultProvider 的 rewrite、rewriteGroup）。
 */

use aes_gcm::aead::{Aead, AeadCore, KeyInit, OsRng};
use aes_gcm::{Aes256Gcm, Key, Nonce};
use sha2::Sha256;
use zeroize::{Zeroize, ZeroizeOnDrop, Zeroizing};

use crate::b64;
use crate::sealed::RawSecrets;

pub const PREFIX: &str = "enc:v1:";
pub const ITERATIONS: u32 = 600_000;
// 資料庫只收這個範圍的次數；超出時不推導（太大會讓手機卡很久，太小不安全）
pub const MIN_ITERATIONS: u32 = 600_000;
pub const MAX_ITERATIONS: u32 = 5_000_000;
pub const CHECK_TEXT: &str = "securibit-vault-check";
const SALT_LENGTH: usize = 16;
const IV_LENGTH: usize = 12;
const TAG_LENGTH: usize = 16;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum VaultError {
    // 密文格式錯誤（不是 enc:v1、base64 不對、長度不夠）
    Format,
    // 解不開：金鑰不對或資料被改過
    Decrypt,
    // 加密設定（salt）格式不對
    Info,
    // 加密設定的版本或 PBKDF2 次數不在允許範圍（不推導金鑰）
    Unsupported,
}

impl std::fmt::Display for VaultError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(match self {
            VaultError::Format => "密文格式錯誤",
            VaultError::Decrypt => "解密失敗",
            VaultError::Info => "加密設定的格式不正確",
            VaultError::Unsupported => "加密設定異常，請聯絡我們",
        })
    }
}

impl std::error::Error for VaultError {}

/// AES-GCM 256 的金鑰（32 位元組），drop 時歸零
#[derive(Clone, Zeroize, ZeroizeOnDrop)]
pub struct VaultKey([u8; 32]);

impl VaultKey {
    pub fn from_bytes(bytes: &[u8]) -> Option<VaultKey> {
        let array: [u8; 32] = bytes.try_into().ok()?;
        Some(VaultKey(array))
    }

    /// 產生隨機金鑰（這台裝置的金鑰用）
    pub fn random() -> VaultKey {
        let mut bytes = [0u8; 32];
        getrandom::getrandom(&mut bytes).expect("系統亂數無法使用");
        let key = VaultKey(bytes);
        bytes.zeroize();
        key
    }

    pub fn as_bytes(&self) -> &[u8; 32] {
        &self.0
    }

    fn cipher(&self) -> Aes256Gcm {
        Aes256Gcm::new(Key::<Aes256Gcm>::from_slice(&self.0))
    }
}

impl std::fmt::Debug for VaultKey {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str("VaultKey(***)")
    }
}

pub fn is_encrypted(value: &str) -> bool {
    value.starts_with(PREFIX)
}

/// PBKDF2-SHA256，密碼以 UTF-8 編碼（同 WebCrypto 的 TextEncoder）
pub fn derive_key(passphrase: &str, salt: &[u8], iterations: u32) -> VaultKey {
    let mut out = [0u8; 32];
    pbkdf2::pbkdf2_hmac::<Sha256>(passphrase.as_bytes(), salt, iterations.max(1), &mut out);
    let key = VaultKey(out);
    out.zeroize();
    key
}

/// 加密成「prefix<iv>:<密文＋tag>」，iv 每次隨機
pub fn encrypt_with_prefix(key: &VaultKey, prefix: &str, text: &[u8]) -> String {
    let iv = Aes256Gcm::generate_nonce(&mut OsRng);
    let cipher = key.cipher().encrypt(&iv, text).expect("AES-GCM 加密不會失敗");
    format!("{prefix}{}:{}", b64::encode(&iv), b64::encode(&cipher))
}

pub fn decrypt_with_prefix(key: &VaultKey, prefix: &str, value: &str) -> Result<Zeroizing<Vec<u8>>, VaultError> {
    let body = value.strip_prefix(prefix).ok_or(VaultError::Format)?;
    let mut parts = body.split(':');
    let (Some(iv), Some(cipher)) = (parts.next(), parts.next()) else {
        return Err(VaultError::Format);
    };
    let iv = b64::decode(iv).ok_or(VaultError::Format)?;
    let cipher = b64::decode(cipher).ok_or(VaultError::Format)?;
    if iv.len() != IV_LENGTH || cipher.len() < TAG_LENGTH {
        return Err(VaultError::Format);
    }
    key.cipher()
        .decrypt(Nonce::from_slice(&iv), cipher.as_ref())
        .map(Zeroizing::new)
        .map_err(|_| VaultError::Decrypt)
}

pub fn encrypt_text(key: &VaultKey, text: &str) -> String {
    encrypt_with_prefix(key, PREFIX, text.as_bytes())
}

/// 解密失敗（密碼不對、資料損毀）回傳錯誤
pub fn decrypt_text(key: &VaultKey, value: &str) -> Result<Zeroizing<String>, VaultError> {
    let plain = decrypt_with_prefix(key, PREFIX, value)?;
    // 先複製再讓 Zeroizing 清掉原本的位元組
    String::from_utf8(plain.to_vec()).map(Zeroizing::new).map_err(|e| {
        let mut bytes = e.into_bytes();
        bytes.zeroize();
        VaultError::Decrypt
    })
}

/// 確認金鑰能解開 check（從裝置讀回來的金鑰也用這個驗證）
pub fn verify_key(check: &str, key: &VaultKey) -> bool {
    matches!(decrypt_text(key, check), Ok(text) if text.as_str() == CHECK_TEXT)
}

/// 用密碼解鎖：salt 是 base64；密碼錯誤回傳 Ok(None)，設定格式不對、次數不在允許範圍回傳錯誤
pub fn unlock(salt_b64: &str, iterations: u32, check: &str, passphrase: &str) -> Result<Option<VaultKey>, VaultError> {
    if !(MIN_ITERATIONS..=MAX_ITERATIONS).contains(&iterations) {
        return Err(VaultError::Unsupported);
    }
    let salt = b64::decode(salt_b64).ok_or(VaultError::Info)?;
    let key = derive_key(passphrase, &salt, iterations);
    Ok(verify_key(check, &key).then_some(key))
}

/// 新的加密設定（設定或更改密碼）：salt、iterations、check 存進 profiles.vault，金鑰留在 Rust
pub struct NewVault {
    pub key: VaultKey,
    // PBKDF2 的 salt（base64）
    pub salt: String,
    pub iterations: u32,
    pub check: String,
}

impl std::fmt::Debug for NewVault {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("NewVault").field("salt", &self.salt).field("check", &self.check).finish_non_exhaustive()
    }
}

/// 同網站 createVault：隨機 16 位元組 salt，PBKDF2 60 萬次，check 是用新金鑰加密的固定字串
pub fn create(passphrase: &str) -> NewVault {
    let mut salt = [0u8; SALT_LENGTH];
    getrandom::getrandom(&mut salt).expect("系統亂數無法使用");
    let key = derive_key(passphrase, &salt, ITERATIONS);
    let check = encrypt_text(&key, CHECK_TEXT);
    NewVault { key, salt: b64::encode(&salt), iterations: ITERATIONS, check }
}

/// 更改密碼、停用加密：每一筆先用舊金鑰解開（本來就是明文的照舊），next 有值就用新金鑰加密，沒有就寫回明文。
/// 有任何一筆解不開就整批失敗（同網站 rewrite）
pub fn reencrypt(raw: &RawSecrets, old: &VaultKey, next: Option<&VaultKey>) -> Result<RawSecrets, VaultError> {
    let mut out = RawSecrets::new();
    for (id, value) in raw {
        let plain = if is_encrypted(value) { decrypt_text(old, value)? } else { value.clone() };
        let value = match next {
            Some(key) => Zeroizing::new(encrypt_text(key, &plain)),
            None => plain,
        };
        out.insert(id.clone(), value);
    }
    Ok(out)
}

/// 開關一個群組的加密：開啟時把明文加密（已經是 enc:v1 的保留），關閉時解開（同網站 rewriteGroup）
pub fn toggle(raw: &RawSecrets, key: &VaultKey, encrypted: bool) -> Result<RawSecrets, VaultError> {
    let mut out = RawSecrets::new();
    for (id, value) in raw {
        let value = match (encrypted, is_encrypted(value)) {
            (true, false) => Zeroizing::new(encrypt_text(key, value)),
            (false, true) => decrypt_text(key, value)?,
            _ => value.clone(),
        };
        out.insert(id.clone(), value);
    }
    Ok(out)
}

#[cfg(test)]
pub(crate) mod tests {
    use super::*;

    /*
     * 測試向量由網站自己的 src/lib/vault/crypto.ts 在 node 產生（tool/gen_vault_vector.sh），
     * 證明解得開網站加密的金鑰，加密的格式也和網站相同。
     */
    pub const PASSPHRASE: &str = "正確的馬 battery staple";
    pub const SECRET: &str = "JBSWY3DPEHPK3PXP";
    pub const SALT: &str = "LFyhBkLr6c+SV0KV3AoamA==";
    pub const CHECK: &str = "enc:v1:jiesZSbsHN+23qmf:N5Z5rC7HuOzTU97AnPcQSWsQgN/8pvEwxR4f5uA5OKNauVYq+Q==";
    pub const CIPHER: &str = "enc:v1:CDD1l4lsiRMJPWzR:ttRxv3VBRdnnlJspFq0iaSNAU/xMK2tcg2LtcQfu+Fo=";

    pub fn website_key() -> VaultKey {
        unlock(SALT, ITERATIONS, CHECK, PASSPHRASE).unwrap().expect("密碼正確")
    }

    #[test]
    fn decrypts_website_vector() {
        let key = website_key();
        assert_eq!(decrypt_text(&key, CIPHER).unwrap().as_str(), SECRET);

        // 自己加密的結果解得回來，格式同網站
        let mine = encrypt_text(&key, SECRET);
        assert!(mine.starts_with("enc:v1:"));
        let parts: Vec<&str> = mine[7..].split(':').collect();
        assert_eq!(b64::decode(parts[0]).unwrap().len(), 12);
        assert_eq!(b64::decode(parts[1]).unwrap().len(), SECRET.len() + 16);
        assert_eq!(decrypt_text(&key, &mine).unwrap().as_str(), SECRET);
        assert_ne!(encrypt_text(&key, SECRET), mine, "iv 每次不同");
    }

    #[test]
    fn wrong_passphrase() {
        assert!(unlock(SALT, ITERATIONS, CHECK, "wrong").unwrap().is_none());
        assert_eq!(unlock("@@", ITERATIONS, CHECK, PASSPHRASE).err(), Some(VaultError::Info));
        // 次數不在允許範圍：不推導（資料被改成很大的數字時不會卡住）
        assert_eq!(unlock(SALT, 1000, CHECK, PASSPHRASE).err(), Some(VaultError::Unsupported));
        assert_eq!(unlock(SALT, 5_000_001, CHECK, PASSPHRASE).err(), Some(VaultError::Unsupported));
    }

    #[test]
    fn rejects_bad_ciphertext() {
        let key = derive_key("x", b"salt", 1);
        assert_eq!(decrypt_text(&key, CIPHER).err(), Some(VaultError::Decrypt));
        assert_eq!(decrypt_text(&key, "enc:v1:abc").err(), Some(VaultError::Format));
        assert_eq!(decrypt_text(&key, "enc:v1:AAAA:AAAA").err(), Some(VaultError::Format));
        assert_eq!(decrypt_text(&key, SECRET).err(), Some(VaultError::Format));
        assert!(!verify_key("garbage", &key));
    }

    #[test]
    fn is_encrypted_prefix() {
        assert!(is_encrypted(CIPHER));
        assert!(!is_encrypted(SECRET));
    }

    fn raw(pairs: &[(&str, &str)]) -> RawSecrets {
        pairs.iter().map(|(k, v)| (k.to_string(), Zeroizing::new(v.to_string()))).collect()
    }

    // 新設定的密碼用網站的 unlock 流程（同一套 PBKDF2、check）解得開，格式同網站 createVault
    #[test]
    fn create_matches_website_format() {
        let next = create("新的密碼 12345678");
        assert_eq!(next.iterations, ITERATIONS);
        assert_eq!(b64::decode(&next.salt).unwrap().len(), 16);
        assert!(next.check.starts_with(PREFIX));
        let again = unlock(&next.salt, next.iterations, &next.check, "新的密碼 12345678").unwrap().expect("密碼正確");
        assert_eq!(again.as_bytes(), next.key.as_bytes());
        assert!(unlock(&next.salt, next.iterations, &next.check, "wrong").unwrap().is_none());
        assert_ne!(create("新的密碼 12345678").salt, next.salt, "salt 每次不同");
    }

    // 網站加密的金鑰（向量）改成新密碼後，用新密碼解得回原文；再改回網站的金鑰，網站的金鑰也解得開
    #[test]
    fn reencrypt_website_vector() {
        let website = website_key();
        let next = create("另一組密碼 abcdefgh");
        let rewritten = reencrypt(&raw(&[("a", CIPHER), ("b", "PLAINTEXT234567")]), &website, Some(&next.key)).unwrap();
        assert!(is_encrypted(&rewritten["a"]) && is_encrypted(&rewritten["b"]));
        assert_eq!(decrypt_text(&next.key, &rewritten["a"]).unwrap().as_str(), SECRET);
        assert_eq!(decrypt_text(&next.key, &rewritten["b"]).unwrap().as_str(), "PLAINTEXT234567");
        assert!(decrypt_text(&website, &rewritten["a"]).is_err());

        let back = reencrypt(&rewritten, &next.key, Some(&website)).unwrap();
        assert_eq!(decrypt_text(&website, &back["a"]).unwrap().as_str(), SECRET);

        // 停用：寫回明文
        let plain = reencrypt(&back, &website, None).unwrap();
        assert_eq!(plain["a"].as_str(), SECRET);
        assert_eq!(plain["b"].as_str(), "PLAINTEXT234567");

        // 有一筆是用別的金鑰加密的：整批失敗
        assert_eq!(reencrypt(&raw(&[("a", CIPHER)]), &next.key, None).err(), Some(VaultError::Decrypt));
    }

    #[test]
    fn toggle_group() {
        let key = website_key();
        let on = toggle(&raw(&[("a", SECRET), ("b", CIPHER)]), &key, true).unwrap();
        assert!(is_encrypted(&on["a"]));
        assert_eq!(on["b"].as_str(), CIPHER, "已經加密的保留");
        assert_eq!(decrypt_text(&key, &on["a"]).unwrap().as_str(), SECRET);

        let off = toggle(&on, &key, false).unwrap();
        assert_eq!(off["a"].as_str(), SECRET);
        assert_eq!(off["b"].as_str(), SECRET);
        assert_eq!(toggle(&off, &key, false).unwrap()["a"].as_str(), SECRET);

        let other = derive_key("x", b"salt", 1);
        assert_eq!(toggle(&raw(&[("b", CIPHER)]), &other, false).err(), Some(VaultError::Decrypt));
    }
}
