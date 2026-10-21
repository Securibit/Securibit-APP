/*
 * 離線快取裡的金鑰用「這台裝置的金鑰」（32 位元組隨機，存在系統安全儲存）封起來，
 * Dart 端只存密文 dev:v1:<iv>:<密文＋tag>，內容是 { 驗證碼 id: 資料庫裡的原始金鑰 } 的 JSON。
 * 加密群組的原始金鑰本來就是 enc:v1 密文，這裡等於再包一層。
 */

use std::collections::BTreeMap;

use zeroize::Zeroizing;

use crate::vault::{decrypt_with_prefix, encrypt_with_prefix, VaultError, VaultKey};

pub const PREFIX: &str = "dev:v1:";

/// 驗證碼 id → 原始金鑰
pub type RawSecrets = BTreeMap<String, Zeroizing<String>>;

pub fn seal(key: &VaultKey, secrets: &RawSecrets) -> String {
    let plain: BTreeMap<&str, &str> = secrets.iter().map(|(k, v)| (k.as_str(), v.as_str())).collect();
    let json = Zeroizing::new(serde_json::to_vec(&plain).expect("字串對字串的 JSON 不會失敗"));
    encrypt_with_prefix(key, PREFIX, &json)
}

pub fn open(key: &VaultKey, blob: &str) -> Result<RawSecrets, VaultError> {
    let json = decrypt_with_prefix(key, PREFIX, blob)?;
    parse_secrets_json(&json).ok_or(VaultError::Format)
}

/// 解析 group_account_secrets() 的回傳（{ id: secret }）；值不是字串時同 Dart 的 asString
pub fn parse_secrets_json(bytes: &[u8]) -> Option<RawSecrets> {
    let value: serde_json::Value = serde_json::from_slice(bytes).ok()?;
    let serde_json::Value::Object(map) = value else {
        // 不是物件（例如 null）就是沒有金鑰
        return Some(RawSecrets::new());
    };
    Some(
        map.into_iter()
            .map(|(id, v)| {
                let text = match v {
                    serde_json::Value::String(s) => s,
                    serde_json::Value::Null => String::new(),
                    other => other.to_string(),
                };
                (id, Zeroizing::new(text))
            })
            .collect(),
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn seal_and_open() {
        let key = VaultKey::random();
        let mut secrets = RawSecrets::new();
        secrets.insert("a".into(), Zeroizing::new("JBSWY3DPEHPK3PXP".into()));
        secrets.insert("b".into(), Zeroizing::new("enc:v1:x:y".into()));
        let blob = seal(&key, &secrets);
        assert!(blob.starts_with(PREFIX));
        assert!(!blob.contains("JBSWY3DP"));
        assert_eq!(open(&key, &blob).unwrap(), secrets);
        assert!(open(&VaultKey::random(), &blob).is_err());
    }

    #[test]
    fn parse_rpc_result() {
        let parsed = parse_secrets_json(br#"{"a":"S1","b":null,"c":5}"#).unwrap();
        assert_eq!(parsed["a"].as_str(), "S1");
        assert_eq!(parsed["b"].as_str(), "");
        assert_eq!(parsed["c"].as_str(), "5");
        assert!(parse_secrets_json(b"null").unwrap().is_empty());
        assert!(parse_secrets_json(b"{").is_none());
    }
}
