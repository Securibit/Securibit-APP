/*
 * 加密密碼的備援（escrow），與網站的實作、網站 scripts/escrow.mjs 逐位元組相容：
 * 團隊保管一把離線的 P-256 私鑰，App 只有公鑰。設定或更改加密密碼時，用公鑰把密碼封成
 *   esc:v1:<kid>:<epk>:<iv>:<ct>（欄位都是標準 base64，含 = 補位；kid 是十六進位）
 *   kid    團隊公鑰（65 位元組未壓縮）SHA-256 的前 16 個十六進位字元
 *   epk    一次性的 P-256 公鑰（65 位元組未壓縮）
 *   shared ECDH(一次性私鑰, 團隊公鑰) 的 x 座標（32 位元組）
 *   key    HKDF-SHA256(ikm = shared, salt = epk, info = "securibit-escrow-v1", 32 位元組)
 *   ct     AES-256-GCM(key, iv 12 位元組, 密碼 UTF-8, AAD = "securibit-escrow-v1:" + 使用者 id)，含 16 位元組 tag
 * 存進資料庫後只有拿著私鑰的人能解開（使用者本人申請或法律要求時才用）。
 */

use aes_gcm::aead::{Aead, AeadCore, KeyInit, OsRng, Payload};
use aes_gcm::{Aes256Gcm, Key};
use hkdf::Hkdf;
use p256::ecdh::EphemeralSecret;
use p256::elliptic_curve::sec1::ToEncodedPoint;
use p256::PublicKey;
use sha2::{Digest, Sha256};
use zeroize::Zeroizing;

use crate::b64;

pub const PREFIX: &str = "esc:v1:";
pub const INFO: &str = "securibit-escrow-v1";

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum EscrowError {
    // 公鑰不是 base64 的 65 位元組未壓縮 P-256 點
    PublicKey,
    // 設定的 kid 和公鑰算出來的不一樣（換金鑰時只改了一半）
    KeyId,
}

impl std::fmt::Display for EscrowError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(match self {
            EscrowError::PublicKey => "備援公鑰的格式不正確",
            EscrowError::KeyId => "備援公鑰和金鑰編號不一致",
        })
    }
}

impl std::error::Error for EscrowError {}

/// 公鑰（原始位元組）的 kid：SHA-256 的前 16 個十六進位字元
pub fn key_id(raw_public: &[u8]) -> String {
    Sha256::digest(raw_public).iter().take(8).map(|b| format!("{b:02x}")).collect()
}

fn parse_public(public_b64: &str) -> Result<(Vec<u8>, PublicKey), EscrowError> {
    let raw = b64::decode(public_b64).ok_or(EscrowError::PublicKey)?;
    // 只收未壓縮格式（04 || x || y），和網站 importKey('raw') 一致
    if raw.len() != 65 || raw[0] != 4 {
        return Err(EscrowError::PublicKey);
    }
    let key = PublicKey::from_sec1_bytes(&raw).map_err(|_| EscrowError::PublicKey)?;
    Ok((raw, key))
}

fn aes_key(shared: &[u8], epk: &[u8]) -> Zeroizing<[u8; 32]> {
    let mut out = Zeroizing::new([0u8; 32]);
    Hkdf::<Sha256>::new(Some(epk), shared).expand(INFO.as_bytes(), out.as_mut()).expect("32 位元組在 HKDF 的長度內");
    out
}

fn aad(user_id: &str) -> Vec<u8> {
    format!("{INFO}:{user_id}").into_bytes()
}

/// 用團隊公鑰把密碼封起來；expected_kid 是設定裡寫的金鑰編號，要和公鑰算出來的一致
pub fn seal(public_b64: &str, expected_kid: &str, user_id: &str, passphrase: &str) -> Result<String, EscrowError> {
    let (raw, team) = parse_public(public_b64)?;
    let kid = key_id(&raw);
    if kid != expected_kid.trim() {
        return Err(EscrowError::KeyId);
    }
    let ephemeral = EphemeralSecret::random(&mut OsRng);
    let epk = ephemeral.public_key().to_encoded_point(false);
    let epk = epk.as_bytes();
    let shared = ephemeral.diffie_hellman(&team);
    let key = aes_key(shared.raw_secret_bytes().as_slice(), epk);
    let cipher = Aes256Gcm::new(Key::<Aes256Gcm>::from_slice(key.as_ref()));
    let iv = Aes256Gcm::generate_nonce(&mut OsRng);
    let aad = aad(user_id);
    let ct = cipher
        .encrypt(&iv, Payload { msg: passphrase.as_bytes(), aad: &aad })
        .expect("AES-GCM 加密不會失敗");
    Ok(format!("{PREFIX}{kid}:{}:{}:{}", b64::encode(epk), b64::encode(&iv), b64::encode(&ct)))
}

#[cfg(test)]
mod tests {
    use super::*;
    use aes_gcm::Nonce;
    use p256::SecretKey;

    // 團隊的「測試」公鑰（不是正式的），和 App 的 lib/features/vault/escrow_key.dart、網站的設定相同
    const TEST_PUBLIC: &str = "BMy8nuvXQTSAUGSnSaTk0VGGcKuX0+BwsG8gf9hXEZJo/MzO8oj0tbK/mFl9chgk64iiJ8098znQHCVGSL8sp+M=";
    const TEST_KID: &str = "405d5c2d185c683b";

    // 測試用的解開（App 本身不需要，也沒有私鑰）：照 scripts/escrow.mjs 的 decrypt
    fn open(secret: &SecretKey, user_id: &str, envelope: &str) -> Option<String> {
        let rest = envelope.strip_prefix(PREFIX)?;
        let parts: Vec<&str> = rest.split(':').collect();
        let [kid, epk, iv, ct] = parts.as_slice() else { return None };
        let own = secret.public_key().to_encoded_point(false);
        if *kid != key_id(own.as_bytes()) {
            return None;
        }
        let epk = b64::decode(epk)?;
        let ephemeral = PublicKey::from_sec1_bytes(&epk).ok()?;
        let shared = p256::ecdh::diffie_hellman(secret.to_nonzero_scalar(), ephemeral.as_affine());
        let key = aes_key(shared.raw_secret_bytes().as_slice(), &epk);
        let cipher = Aes256Gcm::new(Key::<Aes256Gcm>::from_slice(key.as_ref()));
        let iv = b64::decode(iv)?;
        if iv.len() != 12 {
            return None;
        }
        let plain = cipher.decrypt(Nonce::from_slice(&iv), Payload { msg: &b64::decode(ct)?, aad: &aad(user_id) }).ok()?;
        String::from_utf8(plain).ok()
    }

    #[test]
    fn test_key_id_matches_config() {
        let raw = b64::decode(TEST_PUBLIC).unwrap();
        assert_eq!(key_id(&raw), TEST_KID);
    }

    #[test]
    fn seal_and_open_roundtrip() {
        let secret = SecretKey::random(&mut OsRng);
        let public = b64::encode(secret.public_key().to_encoded_point(false).as_bytes());
        let kid = key_id(&b64::decode(&public).unwrap());
        let user = "8d3f0c1e-2b4a-4c6d-9e8f-0a1b2c3d4e5f";
        let envelope = seal(&public, &kid, user, "正確的馬 battery staple").unwrap();

        let parts: Vec<&str> = envelope.strip_prefix(PREFIX).unwrap().split(':').collect();
        assert_eq!(parts.len(), 4);
        assert_eq!(parts[0], kid);
        assert_eq!(b64::decode(parts[1]).unwrap().len(), 65);
        assert_eq!(b64::decode(parts[2]).unwrap().len(), 12);
        // 密文 = 密碼的 UTF-8 長度 + 16 位元組 tag
        assert_eq!(b64::decode(parts[3]).unwrap().len(), "正確的馬 battery staple".len() + 16);

        assert_eq!(open(&secret, user, &envelope).as_deref(), Some("正確的馬 battery staple"));
        // AAD 綁定使用者 id：換人就解不開
        assert_eq!(open(&secret, "someone-else", &envelope), None);
        // 每次的一次性金鑰與 iv 都不同
        assert_ne!(seal(&public, &kid, user, "x").unwrap(), seal(&public, &kid, user, "x").unwrap());
    }

    #[test]
    fn rejects_bad_config() {
        assert_eq!(seal(TEST_PUBLIC, "0000000000000000", "u", "p"), Err(EscrowError::KeyId));
        assert_eq!(seal("not base64!", TEST_KID, "u", "p"), Err(EscrowError::PublicKey));
        // 壓縮格式（33 位元組）不收
        let compressed = b64::encode(&b64::decode(TEST_PUBLIC).unwrap()[..33]);
        assert_eq!(seal(&compressed, TEST_KID, "u", "p"), Err(EscrowError::PublicKey));
    }

    // 互通測試：用測試公鑰封一個信封印出來，交給網站的 scripts/escrow.mjs decrypt 用測試私鑰解開
    //   cargo test -p securibit-core escrow::tests::print_test_envelope -- --nocapture
    #[test]
    fn print_test_envelope() {
        let envelope = seal(TEST_PUBLIC, TEST_KID, "00000000-0000-4000-8000-000000000001", "互通測試 passphrase 123").unwrap();
        println!("ESCROW_ENVELOPE={envelope}");
        assert!(envelope.starts_with("esc:v1:405d5c2d185c683b:"));
    }
}
