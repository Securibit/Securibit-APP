/*
 * 記憶體裡的金鑰保管：依群組 id、驗證碼 id 存放「可以直接產碼」的金鑰（加密群組已解密）。
 * 外面只拿得到驗證碼與「有沒有金鑰、格式對不對」；要顯示或複製金鑰時才用 reveal 取出一份。
 * 每一份金鑰都包在 Zeroizing 裡，被取代、移除或整個清掉時歸零。
 *
 * 封存（seal）：App 鎖定時清掉全部金鑰，並在解鎖前拒絕新的金鑰，避免背景的載入又把金鑰放回來。
 */

use std::collections::HashMap;

use zeroize::Zeroizing;

use crate::sealed::RawSecrets;
use crate::secret::{is_valid_secret, normalize_secret};
use crate::totp::{code_pair, Algorithm};
use crate::vault::{decrypt_text, is_encrypted, VaultKey};

/// 一筆金鑰的公開資訊（不含金鑰本身）
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SecretMeta {
    pub id: String,
    // 正規化後是 Base32（解不開的加密金鑰是 false，畫面顯示「金鑰錯誤」）
    pub valid: bool,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Otp {
    // 沒有這筆金鑰（沒有「查看金鑰」權限、還沒載入，或已鎖定清掉）
    Missing,
    // 金鑰格式錯誤
    Invalid,
    Ready { code: String, next: String },
}

struct GroupSecrets {
    encrypted: bool,
    secrets: HashMap<String, Zeroizing<String>>,
}

#[derive(Default)]
pub struct SecretStore {
    groups: HashMap<String, GroupSecrets>,
    sealed: bool,
}

impl SecretStore {
    pub fn new() -> SecretStore {
        SecretStore::default()
    }

    /// 換掉整個群組的金鑰（舊的歸零）。raw 是資料庫裡的原始值；加密群組給 key 時把 enc:v1 解開，
    /// 解不開的（例如別的裝置用舊密碼寫入）保留原值，產碼時會是 Invalid。
    /// 封存中回傳 None，金鑰直接丟掉。
    pub fn put_group(&mut self, gid: &str, encrypted: bool, raw: RawSecrets, key: Option<&VaultKey>) -> Option<Vec<SecretMeta>> {
        if self.sealed {
            return None;
        }
        let secrets = raw
            .into_iter()
            .map(|(id, value)| {
                let plain = match key {
                    Some(key) if is_encrypted(&value) => decrypt_text(key, &value).unwrap_or(value),
                    _ => value,
                };
                (id, plain)
            })
            .collect();
        self.groups.insert(gid.to_string(), GroupSecrets { encrypted, secrets });
        Some(self.metas(gid))
    }

    pub fn metas(&self, gid: &str) -> Vec<SecretMeta> {
        let Some(group) = self.groups.get(gid) else { return Vec::new() };
        let mut list: Vec<SecretMeta> = group
            .secrets
            .iter()
            .map(|(id, secret)| SecretMeta { id: id.clone(), valid: is_valid_secret(secret) })
            .collect();
        list.sort_by(|a, b| a.id.cmp(&b.id));
        list
    }

    fn get(&self, gid: &str, id: &str) -> Option<&Zeroizing<String>> {
        self.groups.get(gid)?.secrets.get(id)
    }

    pub fn has(&self, gid: &str, id: &str) -> bool {
        self.get(gid, id).is_some()
    }

    /// 第 counter 個週期與下一個週期的驗證碼
    pub fn otp(&self, gid: &str, id: &str, digits: u32, algorithm: Algorithm, counter: i64) -> Otp {
        match self.get(gid, id) {
            None => Otp::Missing,
            Some(secret) => match code_pair(secret, digits, algorithm, counter) {
                None => Otp::Invalid,
                Some(pair) => Otp::Ready { code: pair.code, next: pair.next },
            },
        }
    }

    /// 使用者按了顯示、複製或編輯時才取出（正規化後的）金鑰；格式錯誤的不給
    pub fn reveal(&self, gid: &str, id: &str) -> Option<Zeroizing<String>> {
        let secret = self.get(gid, id)?;
        is_valid_secret(secret).then(|| Zeroizing::new(normalize_secret(secret)))
    }

    pub fn remove(&mut self, gid: &str, id: &str) {
        if let Some(group) = self.groups.get_mut(gid) {
            group.secrets.remove(id);
        }
    }

    pub fn clear_group(&mut self, gid: &str) {
        self.groups.remove(gid);
    }

    /// 只留下這些群組（離開或被移出的群組清掉）
    pub fn retain_groups(&mut self, gids: &[String]) {
        self.groups.retain(|gid, _| gids.iter().any(|g| g == gid));
    }

    /// 加密群組鎖定時清掉所有加密群組的金鑰
    pub fn clear_encrypted(&mut self) {
        self.groups.retain(|_, group| !group.encrypted);
    }

    pub fn clear_all(&mut self) {
        self.groups.clear();
    }

    pub fn seal(&mut self) {
        self.sealed = true;
        self.clear_all();
    }

    pub fn unseal(&mut self) {
        self.sealed = false;
    }

    pub fn is_sealed(&self) -> bool {
        self.sealed
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::vault::tests::{website_key, CIPHER, SECRET};

    fn raw(pairs: &[(&str, &str)]) -> RawSecrets {
        pairs.iter().map(|(k, v)| (k.to_string(), Zeroizing::new(v.to_string()))).collect()
    }

    #[test]
    fn codes_without_exposing_secrets() {
        let mut store = SecretStore::new();
        let metas = store.put_group("g", false, raw(&[("a", "jbsw y3dp ehpk 3pxp"), ("b", "!!!")]), None).unwrap();
        assert_eq!(metas, vec![SecretMeta { id: "a".into(), valid: true }, SecretMeta { id: "b".into(), valid: false }]);
        let counter = 1_700_000_000 / 30;
        assert_eq!(
            store.otp("g", "a", 6, Algorithm::Sha1, counter),
            Otp::Ready { code: "324550".into(), next: crate::totp::generate(SECRET, 6, 30, Algorithm::Sha1, (counter + 1) * 30_000).unwrap() }
        );
        assert_eq!(store.otp("g", "b", 6, Algorithm::Sha1, counter), Otp::Invalid);
        assert_eq!(store.otp("g", "c", 6, Algorithm::Sha1, counter), Otp::Missing);
        assert_eq!(store.reveal("g", "a").unwrap().as_str(), SECRET);
        assert!(store.reveal("g", "b").is_none());

        store.remove("g", "a");
        assert!(!store.has("g", "a"));
    }

    #[test]
    fn encrypted_groups_decrypt_and_clear_on_vault_lock() {
        let key = website_key();
        let mut store = SecretStore::new();
        store.put_group("plain", false, raw(&[("p", SECRET)]), None);
        let metas = store.put_group("vault", true, raw(&[("v", CIPHER), ("bad", "enc:v1:AAAAAAAAAAAAAAAA:AAAAAAAAAAAAAAAAAAAAAA==")]), Some(&key)).unwrap();
        assert_eq!(metas.iter().map(|m| m.valid).collect::<Vec<_>>(), vec![false, true]);
        assert_eq!(store.reveal("vault", "v").unwrap().as_str(), SECRET);

        store.clear_encrypted();
        assert!(!store.has("vault", "v"));
        assert!(store.has("plain", "p"));

        // 沒有金鑰時保留密文，產碼是 Invalid
        store.put_group("vault", true, raw(&[("v", CIPHER)]), None);
        assert_eq!(store.otp("vault", "v", 6, Algorithm::Sha1, 0), Otp::Invalid);
    }

    #[test]
    fn seal_rejects_new_secrets() {
        let mut store = SecretStore::new();
        store.put_group("g", false, raw(&[("a", SECRET)]), None);
        store.seal();
        assert!(!store.has("g", "a"));
        assert!(store.put_group("g", false, raw(&[("a", SECRET)]), None).is_none());
        assert!(!store.has("g", "a"));
        store.unseal();
        assert!(store.put_group("g", false, raw(&[("a", SECRET)]), None).is_some());
        store.retain_groups(&["other".into()]);
        assert!(!store.has("g", "a"));
    }
}
