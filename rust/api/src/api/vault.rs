/*
 * 加密群組的解鎖（同網站 VaultProvider；設定、更改、停用加密請到網站）。
 * 解開的金鑰只放在 Rust 的記憶體；「在這台裝置記住」時用這台裝置的金鑰包起來，Dart 只存包過的密文。
 */

use flutter_rust_bridge::frb;
use securibit_core::vault::{self, VaultKey};
use zeroize::Zeroizing;

use crate::state::state;

const WRAP_PREFIX: &str = "dev:v1:";

pub enum VaultUnlockResult {
    Unlocked,
    WrongPassphrase,
    // 加密設定（salt）格式不對
    BadInfo,
}

/// 用密碼解鎖（PBKDF2 60 萬次，在背景執行緒計算）；成功時金鑰留在 Rust
pub fn vault_unlock(salt: String, iterations: u32, check: String, passphrase: String) -> VaultUnlockResult {
    let passphrase = Zeroizing::new(passphrase);
    match vault::unlock(&salt, iterations, &check, &passphrase) {
        Ok(Some(key)) => {
            state().vault = Some(key);
            VaultUnlockResult::Unlocked
        }
        Ok(None) => VaultUnlockResult::WrongPassphrase,
        Err(_) => VaultUnlockResult::BadInfo,
    }
}

/// 鎖定：金鑰歸零，加密群組的驗證碼金鑰也一起清掉
#[frb(sync)]
pub fn vault_lock() {
    let mut state = state();
    state.vault = None;
    state.store.clear_encrypted();
}

#[frb(sync)]
pub fn vault_is_unlocked() -> bool {
    state().vault.is_some()
}

/// 「在這台裝置記住」：用這台裝置的金鑰把解開的金鑰包起來給 Dart 存；還沒解鎖是 null
#[frb(sync)]
pub fn vault_export_wrapped() -> Option<String> {
    let mut state = state();
    let key = state.vault.clone()?;
    Some(vault::encrypt_with_prefix(state.device_key(), WRAP_PREFIX, key.as_bytes()))
}

/// 讀回記住的金鑰；要能解開 check 才採用（別的裝置改過密碼就不再使用）
#[frb(sync)]
pub fn vault_restore_wrapped(check: String, wrapped: String) -> bool {
    let mut state = state();
    let Ok(bytes) = vault::decrypt_with_prefix(state.device_key(), WRAP_PREFIX, &wrapped) else { return false };
    adopt(&mut state, &check, &bytes)
}

/// 舊版（改用 Rust 之前）直接存 base64 金鑰的格式；讀回來後 Dart 會改存成包過的格式
#[frb(sync)]
pub fn vault_restore_legacy(check: String, key_base64: String) -> bool {
    use base64::engine::general_purpose::STANDARD;
    use base64::Engine;
    let Ok(bytes) = STANDARD.decode(key_base64.trim()) else { return false };
    let bytes = Zeroizing::new(bytes);
    let key_base64 = Zeroizing::new(key_base64);
    drop(key_base64);
    adopt(&mut state(), &check, &bytes)
}

fn adopt(state: &mut crate::state::State, check: &str, bytes: &[u8]) -> bool {
    let Some(key) = VaultKey::from_bytes(bytes) else { return false };
    if !vault::verify_key(check, &key) {
        return false;
    }
    state.vault = Some(key);
    true
}

/// 加密群組新增或修改金鑰時先在這裡加密成 enc:v1；還沒解鎖是 null
#[frb(sync)]
pub fn vault_encrypt(text: String) -> Option<String> {
    let text = Zeroizing::new(text);
    let state = state();
    let key = state.vault.as_ref()?;
    Some(vault::encrypt_text(key, &text))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::api::secrets::{secrets_put, secrets_reveal};

    const SALT: &str = "LFyhBkLr6c+SV0KV3AoamA==";
    const CHECK: &str = "enc:v1:jiesZSbsHN+23qmf:N5Z5rC7HuOzTU97AnPcQSWsQgN/8pvEwxR4f5uA5OKNauVYq+Q==";
    const PASSPHRASE: &str = "正確的馬 battery staple";

    // 舊版直接存 base64 金鑰：讀回來要驗證 check，之後改存成用裝置金鑰包過的格式
    #[test]
    fn legacy_and_wrapped_device_key() {
        use base64::engine::general_purpose::STANDARD;
        use base64::Engine;
        let salt = STANDARD.decode(SALT).unwrap();
        let key = vault::derive_key(PASSPHRASE, &salt, vault::ITERATIONS);
        let legacy = STANDARD.encode(key.as_bytes());

        assert!(!vault_restore_legacy("enc:v1:AAAAAAAAAAAAAAAA:AAAAAAAAAAAAAAAAAAAAAA==".into(), legacy.clone()));
        assert!(!vault_restore_legacy(CHECK.into(), "short".into()));
        assert!(vault_restore_legacy(CHECK.into(), legacy));
        assert!(vault_is_unlocked());

        let wrapped = vault_export_wrapped().unwrap();
        assert!(wrapped.starts_with("dev:v1:"));
        vault_lock();
        assert!(!vault_is_unlocked());
        assert!(vault_encrypt("x".into()).is_none());
        assert!(vault_restore_wrapped(CHECK.into(), wrapped));

        // 加密群組以外的 scope 不受鎖定影響
        secrets_put("plain".into(), [("a".to_string(), "jbsw y3dp".to_string())].into());
        vault_lock();
        assert_eq!(secrets_reveal("plain".into(), "a".into()).as_deref(), Some("JBSWY3DP"));
    }
}
