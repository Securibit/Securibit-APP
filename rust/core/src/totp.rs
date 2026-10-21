/*
 * TOTP（RFC 6238）：counter = floor(時間 / 週期)，HMAC 後做動態截斷取 digits 位數。
 * 結果與網站用的 totp-generator 相同；金鑰不合法時回傳 None（畫面顯示「金鑰錯誤」）。
 */

use hmac::{Hmac, Mac};
use sha1::Sha1;
use sha2::{Sha256, Sha512};
use zeroize::Zeroizing;

use crate::base32;
use crate::secret::{is_base32, normalize_secret};

/// 資料庫與畫面上的寫法：SHA-1 / SHA-256 / SHA-512
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Default)]
pub enum Algorithm {
    #[default]
    Sha1,
    Sha256,
    Sha512,
}

impl Algorithm {
    pub const ALL: [Algorithm; 3] = [Algorithm::Sha1, Algorithm::Sha256, Algorithm::Sha512];

    pub fn label(self) -> &'static str {
        match self {
            Algorithm::Sha1 => "SHA-1",
            Algorithm::Sha256 => "SHA-256",
            Algorithm::Sha512 => "SHA-512",
        }
    }

    /// 不認得的寫法用預設值（同 Dart 的 TotpAlgorithm.fromLabel）
    pub fn from_label(value: &str) -> Algorithm {
        Self::ALL.into_iter().find(|a| a.label() == value).unwrap_or_default()
    }
}

// 與 Google Authenticator 相同
pub const DEFAULT_DIGITS: u32 = 6;
pub const DEFAULT_PERIOD: u32 = 30;
pub const DIGITS_OPTIONS: [u32; 2] = [6, 8];
pub const PERIOD_OPTIONS: [u32; 2] = [30, 60];

fn mac<M: Mac + hmac::digest::KeyInit>(key: &[u8], message: &[u8]) -> Vec<u8> {
    let mut mac = <M as hmac::digest::KeyInit>::new_from_slice(key).expect("HMAC 接受任何長度的金鑰");
    mac.update(message);
    mac.finalize().into_bytes().to_vec()
}

/// HOTP（RFC 4226）：key 是原始金鑰位元組
pub fn hotp(key: &[u8], counter: i64, digits: u32, algorithm: Algorithm) -> String {
    let message = counter.to_be_bytes();
    let digest = Zeroizing::new(match algorithm {
        Algorithm::Sha1 => mac::<Hmac<Sha1>>(key, &message),
        Algorithm::Sha256 => mac::<Hmac<Sha256>>(key, &message),
        Algorithm::Sha512 => mac::<Hmac<Sha512>>(key, &message),
    });
    let offset = (digest[digest.len() - 1] & 0x0f) as usize;
    let binary = ((digest[offset] as u64 & 0x7f) << 24)
        | ((digest[offset + 1] as u64) << 16)
        | ((digest[offset + 2] as u64) << 8)
        | digest[offset + 3] as u64;
    let modulo = 10u64.pow(digits.min(18));
    format!("{:0width$}", binary % modulo, width = digits as usize)
}

/// 把金鑰轉成原始位元組；不合法時是 None
pub fn secret_bytes(secret: &str) -> Option<Zeroizing<Vec<u8>>> {
    let normalized = Zeroizing::new(normalize_secret(secret));
    if !is_base32(&normalized) {
        return None;
    }
    base32::decode(&normalized).ok().map(Zeroizing::new)
}

// 同 Dart 的 ~/（往 0 取整）
fn counter_at(timestamp_ms: i64, period: u32) -> i64 {
    timestamp_ms / 1000 / period.max(1) as i64
}

/// 某個時間點的驗證碼
pub fn generate(secret: &str, digits: u32, period: u32, algorithm: Algorithm, timestamp_ms: i64) -> Option<String> {
    let key = secret_bytes(secret)?;
    Some(hotp(&key, counter_at(timestamp_ms, period), digits, algorithm))
}

/// 第 counter 個週期與下一個週期的驗證碼（快到期時畫面會顯示下一組）
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CodePair {
    pub code: String,
    pub next: String,
}

pub fn code_pair(secret: &str, digits: u32, algorithm: Algorithm, counter: i64) -> Option<CodePair> {
    let key = secret_bytes(secret)?;
    Some(CodePair {
        code: hotp(&key, counter, digits, algorithm),
        next: hotp(&key, counter + 1, digits, algorithm),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    // RFC 6238 附錄 B 的測試向量（8 位數、30 秒）；三種演算法的金鑰長度不同
    #[test]
    fn rfc6238_vectors() {
        let keys = [
            (Algorithm::Sha1, "12345678901234567890"),
            (Algorithm::Sha256, "12345678901234567890123456789012"),
            (Algorithm::Sha512, "1234567890123456789012345678901234567890123456789012345678901234"),
        ];
        let vectors: [(i64, [&str; 3]); 6] = [
            (59, ["94287082", "46119246", "90693936"]),
            (1111111109, ["07081804", "68084774", "25091201"]),
            (1111111111, ["14050471", "67062674", "99943326"]),
            (1234567890, ["89005924", "91819424", "93441116"]),
            (2000000000, ["69279037", "90698825", "38618901"]),
            (20000000000, ["65353130", "77737706", "47863826"]),
        ];
        for (time, expected) in vectors {
            for (i, (algorithm, key)) in keys.iter().enumerate() {
                let secret = base32::encode(key.as_bytes());
                assert_eq!(
                    generate(&secret, 8, 30, *algorithm, time * 1000).as_deref(),
                    Some(expected[i]),
                    "{} @ {time}",
                    algorithm.label()
                );
            }
        }
    }

    // 用網站實際使用的 totp-generator（node）產生的結果比對
    #[test]
    fn matches_website_totp_generator() {
        assert_eq!(generate("JBSWY3DPEHPK3PXP", 6, 30, Algorithm::Sha1, 1_700_000_000_000).as_deref(), Some("324550"));
        assert_eq!(
            generate("jbsw y3dp ehpk 3pxp", 8, 60, Algorithm::Sha256, 1_700_000_000_000).as_deref(),
            Some("71205722")
        );
        assert_eq!(
            generate("GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ", 8, 30, Algorithm::Sha512, 1_234_567_890_000).as_deref(),
            Some("76671578")
        );
    }

    #[test]
    fn invalid_secret() {
        assert_eq!(generate("not base32!", 6, 30, Algorithm::Sha1, 0), None);
        assert_eq!(generate("", 6, 30, Algorithm::Sha1, 0), None);
        assert_eq!(generate("enc:v1:abc:def", 6, 30, Algorithm::Sha1, 0), None);
    }

    #[test]
    fn pair_is_this_and_next_period() {
        let pair = code_pair("JBSWY3DPEHPK3PXP", 6, Algorithm::Sha1, 1_700_000_000 / 30).unwrap();
        assert_eq!(pair.code, "324550");
        assert_eq!(
            Some(pair.next),
            generate("JBSWY3DPEHPK3PXP", 6, 30, Algorithm::Sha1, 1_700_000_000_000 + 30_000)
        );
    }

    #[test]
    fn labels() {
        assert_eq!(Algorithm::from_label("SHA-256"), Algorithm::Sha256);
        assert_eq!(Algorithm::from_label("MD5"), Algorithm::Sha1);
        assert_eq!(Algorithm::Sha512.label(), "SHA-512");
    }
}
