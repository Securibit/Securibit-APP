/*
 * 加密群組（同網站 VaultProvider）：解鎖、設定／更改／停用加密密碼、開關群組加密。
 * 解開的金鑰只放在 Rust 的記憶體；「在這台裝置記住」時用這台裝置的金鑰包起來，Dart 只存包過的密文。
 * 設定或更改密碼時，新金鑰先暫存在 Rust（pending），伺服器存好才換上；
 * 要重新加密的金鑰由這裡直接連 Supabase 取得、解密、加密再寫回，全程不經過 Dart。
 */

use flutter_rust_bridge::frb;
use securibit_core::sealed::RawSecrets;
use securibit_core::escrow;
use securibit_core::vault::{self, VaultError, VaultKey};
use zeroize::Zeroizing;

use crate::api::secrets::SupabaseConnection;
use crate::net;
use crate::state::state;

// 錯誤訊息同網站 VaultProvider
const WRONG_PASSPHRASE: &str = "密碼錯誤";
const UNDECRYPTABLE: &str = "有金鑰無法解密，可能是在其他裝置用舊密碼新增的。請先刪除顯示「金鑰錯誤」的項目再試一次。";
const CHANGED_ELSEWHERE: &str = "加密設定已在其他裝置變更，請重新整理";
const UNSUPPORTED: &str = "加密設定異常，請聯絡我們";

const WRAP_PREFIX: &str = "dev:v1:";

pub enum VaultUnlockResult {
    Unlocked,
    WrongPassphrase,
    // 加密設定（salt）格式不對
    BadInfo,
    // PBKDF2 次數不在允許範圍（600,000～5,000,000），不推導金鑰
    Unsupported,
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
        Err(VaultError::Unsupported) => VaultUnlockResult::Unsupported,
        Err(_) => VaultUnlockResult::BadInfo,
    }
}

/// 鎖定：金鑰歸零，加密群組的驗證碼金鑰也一起清掉（還沒存好的新設定也丟掉）
#[frb(sync)]
pub fn vault_lock() {
    let mut state = state();
    state.vault = None;
    state.pending = None;
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

// ---------- 密碼備援（escrow） ----------

/// 用團隊的公鑰把加密密碼封成 esc:v1 備援密文（設定、更改密碼時與解鎖後補存用）。
/// public_key、key_id 來自 Dart 的備援金鑰設定；兩者不一致或格式不對時回傳錯誤訊息
#[frb(sync)]
pub fn escrow_seal(public_key: String, key_id: String, user_id: String, passphrase: String) -> Result<String, String> {
    let passphrase = Zeroizing::new(passphrase);
    escrow::seal(&public_key, &key_id, &user_id, &passphrase).map_err(|error| error.to_string())
}

// ---------- 設定、更改、停用加密密碼 ----------

/// 新的加密設定裡可以公開的部分（存進 profiles.vault）
pub struct VaultSetup {
    pub salt: String,
    pub iterations: u32,
    pub check: String,
}

/// 目前的加密設定與使用者輸入的目前密碼（更改密碼、停用時要先用它解開舊的金鑰）
pub struct VaultCurrent {
    pub salt: String,
    pub iterations: u32,
    pub check: String,
    pub passphrase: String,
}

/// 設定或更改密碼的第一步：產生新的加密設定（PBKDF2 60 萬次，在背景執行緒計算），
/// 新金鑰暫存在 Rust、還沒生效，要等 vault_rewrite_all 存到伺服器才換上
pub fn vault_create(passphrase: String) -> VaultSetup {
    let passphrase = Zeroizing::new(passphrase);
    let next = vault::create(&passphrase);
    let setup = VaultSetup { salt: next.salt.clone(), iterations: next.iterations, check: next.check.clone() };
    state().pending = Some(next);
    setup
}

/// 用新的加密設定重新寫入「我擁有且已加密的群組」的全部金鑰（同網站 VaultProvider 的 rewrite、enable）：
/// - 設定密碼：current 是 null、use_pending 是 true；還沒有加密的群組，只存加密設定
/// - 更改密碼：current 有值、use_pending 是 true；用舊金鑰解開，新金鑰加密
/// - 停用加密：current 有值、use_pending 是 false；解開後寫回明文，群組改成沒加密
/// expected_check 是目前 profile 的 vault.check（未啟用是 null），別的裝置先改過時資料庫會拒絕。
/// escrow 是用 escrow_seal 把新密碼封起來的備援密文（停用時不用給），和新的設定一起存進資料庫。
/// 成功回傳 null；失敗回傳給使用者看的訊息。成功後新金鑰（停用時是沒有金鑰）立即生效，加密群組的驗證碼金鑰要重新讀取
pub async fn vault_rewrite_all(
    connection: SupabaseConnection,
    current: Option<VaultCurrent>,
    use_pending: bool,
    expected_check: Option<String>,
    escrow: Option<String>,
) -> Option<String> {
    let next = if use_pending {
        match state().pending.take() {
            Some(next) => Some(next),
            None => return Some("新的加密設定已失效，請再試一次".into()),
        }
    } else {
        None
    };
    if current.is_none() && next.is_none() {
        return Some("尚未啟用加密".into());
    }

    // 舊的金鑰：用目前的密碼解開，順便確認密碼正確
    let old = match current {
        Some(current) => {
            let passphrase = Zeroizing::new(current.passphrase);
            match vault::unlock(&current.salt, current.iterations, &current.check, &passphrase) {
                Ok(Some(key)) => Some(key),
                Ok(None) => return Some(WRONG_PASSPHRASE.into()),
                Err(VaultError::Unsupported) => return Some(UNSUPPORTED.into()),
                Err(_) => return Some("加密設定的格式不正確".into()),
            }
        }
        None => None,
    };

    // 設定密碼時還沒有加密的群組，不用讀金鑰（同網站 enable）
    let secrets = match &old {
        Some(old) => {
            let raw = match load_encrypted_secrets(&connection).await {
                Ok(raw) => raw,
                Err(message) => return Some(message),
            };
            match vault::reencrypt(&raw, old, next.as_ref().map(|n| &n.key)) {
                Ok(secrets) => secrets,
                Err(_) => return Some(UNDECRYPTABLE.into()),
            }
        }
        None => RawSecrets::new(),
    };

    let new_vault = next.as_ref().map(|n| {
        serde_json::json!({ "v": 1, "salt": n.salt, "iterations": n.iterations, "check": n.check }).to_string()
    });
    // 停用時沒有新密碼，不送備援
    let escrow = if next.is_some() { escrow } else { None };
    if let Err(error) =
        net::totp_set_vault(&connection, new_vault.as_deref(), &secrets, expected_check.as_deref(), escrow.as_deref()).await
    {
        return Some(error.message);
    }

    let mut state = state();
    state.vault = next.map(|n| n.key.clone());
    state.store.clear_encrypted();
    None
}

// 我擁有且已加密的群組裡全部驗證碼的金鑰（資料庫裡的原始值）
async fn load_encrypted_secrets(connection: &SupabaseConnection) -> Result<RawSecrets, String> {
    let gids = net::my_encrypted_groups(connection).await.map_err(|e| e.message)?;
    let mut all = RawSecrets::new();
    for gid in gids {
        let raw = net::group_account_secrets(connection, &gid).await.map_err(|e| e.message)?;
        all.extend(raw);
    }
    Ok(all)
}

/// 開關一個群組的加密（同網站 rewriteGroup）：用目前解鎖的金鑰把群組裡的金鑰加密或解開，再整批寫回。
/// expected_check 是目前 profile 的 vault.check；成功回傳 null，失敗回傳給使用者看的訊息
pub async fn vault_set_group_encrypted(
    connection: SupabaseConnection,
    gid: String,
    encrypted: bool,
    expected_check: String,
) -> Option<String> {
    let Some(key) = state().vault.clone() else { return Some("請先輸入加密密碼解鎖".into()) };
    // 解鎖的金鑰要和目前的設定相符，才不會用別組密碼加密
    if !vault::verify_key(&expected_check, &key) {
        return Some(CHANGED_ELSEWHERE.into());
    }
    let raw = match net::group_account_secrets(&connection, &gid).await {
        Ok(raw) => raw,
        Err(error) => return Some(error.message),
    };
    let secrets = match vault::toggle(&raw, &key, encrypted) {
        Ok(secrets) => secrets,
        Err(_) => return Some(UNDECRYPTABLE.into()),
    };
    net::group_set_encrypted(&connection, &gid, encrypted, &secrets, &expected_check).await.err().map(|e| e.message)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::api::secrets::{secrets_put, secrets_reveal};

    const SALT: &str = "LFyhBkLr6c+SV0KV3AoamA==";
    const CHECK: &str = "enc:v1:jiesZSbsHN+23qmf:N5Z5rC7HuOzTU97AnPcQSWsQgN/8pvEwxR4f5uA5OKNauVYq+Q==";
    const PASSPHRASE: &str = "正確的馬 battery staple";
    // 網站產生的向量（同 rust/core/src/vault.rs 的測試）：用上面的密碼加密的 JBSWY3DPEHPK3PXP
    const SECRET: &str = "JBSWY3DPEHPK3PXP";
    const CIPHER: &str = "enc:v1:CDD1l4lsiRMJPWzR:ttRxv3VBRdnnlJspFq0iaSNAU/xMK2tcg2LtcQfu+Fo=";

    // 這些測試共用 Rust 的全域狀態，一次只跑一個
    static SERIAL: std::sync::Mutex<()> = std::sync::Mutex::new(());

    fn serial() -> std::sync::MutexGuard<'static, ()> {
        SERIAL.lock().unwrap_or_else(|poisoned| poisoned.into_inner())
    }

    // 舊版直接存 base64 金鑰：讀回來要驗證 check，之後改存成用裝置金鑰包過的格式
    #[test]
    fn legacy_and_wrapped_device_key() {
        let _serial = serial();
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

    // ---------- 設定、更改、停用與群組加密：對本機的假 Supabase 跑完整流程 ----------

    use std::collections::BTreeMap;
    use std::io::{BufRead, BufReader, Read, Write};
    use std::net::TcpListener;
    use std::sync::{Arc, Mutex};

    use serde_json::{json, Value};

    // 假的資料庫：群組（id、是不是我的、加密）、各群組的金鑰、目前的 vault.check，以及收到的請求
    #[derive(Default)]
    struct FakeDb {
        groups: Vec<(String, bool, bool)>,
        secrets: BTreeMap<String, BTreeMap<String, String>>,
        check: Option<String>,
        requests: Vec<(String, Value)>,
        // 還沒有 escrow 參數的舊資料庫
        legacy: bool,
    }

    fn fake_supabase(db: Arc<Mutex<FakeDb>>) -> SupabaseConnection {
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let url = format!("http://{}", listener.local_addr().unwrap());
        std::thread::spawn(move || {
            for stream in listener.incoming() {
                let Ok(mut stream) = stream else { continue };
                let mut reader = BufReader::new(stream.try_clone().unwrap());
                let mut line = String::new();
                reader.read_line(&mut line).unwrap();
                let path = line.split_whitespace().nth(1).unwrap_or("").to_string();
                let mut length = 0;
                loop {
                    let mut header = String::new();
                    reader.read_line(&mut header).unwrap();
                    if header.trim().is_empty() {
                        break;
                    }
                    if let Some((name, value)) = header.split_once(':') {
                        if name.eq_ignore_ascii_case("content-length") {
                            length = value.trim().parse().unwrap();
                        }
                    }
                }
                let mut body = vec![0; length];
                reader.read_exact(&mut body).unwrap();
                let params: Value = serde_json::from_slice(&body).unwrap_or(Value::Null);
                let function = path.trim_start_matches("/rest/v1/rpc/").to_string();
                let (status, response) = handle(&mut db.lock().unwrap(), &function, &params);
                db.lock().unwrap().requests.push((function, params));
                let reply = format!(
                    "HTTP/1.1 {status} X\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{response}",
                    response.len()
                );
                stream.write_all(reply.as_bytes()).unwrap();
            }
        });
        SupabaseConnection { url, anon_key: "anon".into(), access_token: "token".into(), user_agent: "test".into() }
    }

    fn error(message: &str) -> (u16, String) {
        (400, json!({ "code": "P0001", "message": message }).to_string())
    }

    // 只模擬會用到的 RPC 與資料庫的檢查（expected_check、金鑰格式）
    fn handle(db: &mut FakeDb, function: &str, params: &Value) -> (u16, String) {
        match function {
            "my_groups" => {
                let list: Vec<Value> =
                    db.groups.iter().map(|(id, owner, enc)| json!({ "id": id, "is_owner": owner, "encrypted": enc })).collect();
                (200, Value::Array(list).to_string())
            }
            "group_account_secrets" => {
                let gid = params["gid"].as_str().unwrap();
                (200, json!(db.secrets.get(gid).cloned().unwrap_or_default()).to_string())
            }
            "totp_set_vault" => {
                if db.legacy && params.get("escrow").is_some() {
                    return (404, json!({ "code": "PGRST202", "message": "no" }).to_string());
                }
                if params["expected_check"].as_str() != db.check.as_deref() {
                    return error(CHANGED_ELSEWHERE);
                }
                let next = params["new_vault"]["check"].as_str().map(str::to_string);
                let enc: Vec<String> = db.groups.iter().filter(|g| g.1 && g.2).map(|g| g.0.clone()).collect();
                for gid in &enc {
                    for (id, secret) in db.secrets.get_mut(gid).unwrap().iter_mut() {
                        let Some(value) = params["secrets"][id].as_str() else { return error("驗證碼清單已在其他裝置變更，請重新整理後再試") };
                        if next.is_some() != value.starts_with("enc:v1:") {
                            return error("金鑰格式和加密設定不一致，請重新整理後再試");
                        }
                        *secret = value.to_string();
                    }
                }
                if next.is_none() {
                    for group in db.groups.iter_mut() {
                        group.2 = false;
                    }
                }
                db.check = next;
                (200, "[]".into())
            }
            "group_set_encrypted" => {
                if params["expected_check"].as_str() != db.check.as_deref() {
                    return error(CHANGED_ELSEWHERE);
                }
                let gid = params["gid"].as_str().unwrap();
                let on = params["encrypted"].as_bool().unwrap();
                for (id, secret) in db.secrets.get_mut(gid).unwrap().iter_mut() {
                    let value = params["secrets"][id].as_str().unwrap();
                    if on != value.starts_with("enc:v1:") {
                        return error("金鑰格式和加密設定不一致，請重新整理後再試");
                    }
                    *secret = value.to_string();
                }
                db.groups.iter_mut().find(|g| g.0 == gid).unwrap().2 = on;
                (200, "".into())
            }
            _ => (404, json!({ "code": "PGRST202", "message": "no" }).to_string()),
        }
    }

    fn block_on<F: std::future::Future>(future: F) -> F::Output {
        tokio::runtime::Builder::new_current_thread().enable_all().build().unwrap().block_on(future)
    }

    fn current(salt: &str, check: &str, passphrase: &str) -> Option<VaultCurrent> {
        Some(VaultCurrent { salt: salt.into(), iterations: vault::ITERATIONS, check: check.into(), passphrase: passphrase.into() })
    }

    fn secrets_of(db: &Arc<Mutex<FakeDb>>, gid: &str) -> BTreeMap<String, String> {
        db.lock().unwrap().secrets[gid].clone()
    }

    fn calls(db: &Arc<Mutex<FakeDb>>, function: &str) -> usize {
        db.lock().unwrap().requests.iter().filter(|(f, _)| f == function).count()
    }

    // 網站加密的群組（向量）改密碼 → 新密碼解得開；再停用 → 寫回明文
    #[test]
    fn change_and_disable_with_website_vector() {
        let _serial = serial();
        vault_lock();
        let db = Arc::new(Mutex::new(FakeDb {
            groups: vec![("mine".into(), true, true), ("plain".into(), true, false), ("theirs".into(), false, true)],
            secrets: BTreeMap::from([
                ("mine".into(), BTreeMap::from([("a".into(), CIPHER.into()), ("b".into(), "PLAINTEXT234567".into())])),
                ("plain".into(), BTreeMap::from([("c".into(), SECRET.into())])),
                ("theirs".into(), BTreeMap::from([("d".into(), CIPHER.into())])),
            ]),
            check: Some(CHECK.into()),
            ..Default::default()
        }));
        let connection = || fake_supabase(db.clone());

        // 目前的密碼錯誤：不送出任何東西
        vault_create("新的密碼 abcdefgh".into());
        let wrong = block_on(vault_rewrite_all(connection(), current(SALT, CHECK, "wrong"), true, Some(CHECK.into()), None));
        assert_eq!(wrong.as_deref(), Some(WRONG_PASSPHRASE));
        assert_eq!(calls(&db, "totp_set_vault"), 0);
        // 用過的新設定就丟掉了
        let again = block_on(vault_rewrite_all(connection(), current(SALT, CHECK, PASSPHRASE), true, Some(CHECK.into()), None));
        assert_eq!(again.as_deref(), Some("新的加密設定已失效，請再試一次"));

        // 更改密碼
        let setup = vault_create("新的密碼 abcdefgh".into());
        assert!(!vault_is_unlocked(), "存到伺服器前新金鑰還沒生效");
        let changed = block_on(vault_rewrite_all(
            connection(),
            current(SALT, CHECK, PASSPHRASE),
            true,
            Some(CHECK.into()),
            Some("esc:v1:kid:epk:iv:ct".into()),
        ));
        assert_eq!(changed, None);
        assert!(vault_is_unlocked());
        let sent = db.lock().unwrap().requests.iter().rev().find(|(f, _)| f == "totp_set_vault").unwrap().1.clone();
        assert_eq!(sent["new_vault"], json!({ "v": 1, "salt": setup.salt, "iterations": setup.iterations, "check": setup.check }));
        assert_eq!(sent["expected_check"], json!(CHECK));
        assert_eq!(sent["escrow"], json!("esc:v1:kid:epk:iv:ct"));
        // 只送我擁有且已加密的群組
        assert_eq!(sent["secrets"].as_object().unwrap().keys().collect::<Vec<_>>(), ["a", "b"]);
        assert_eq!(calls(&db, "group_account_secrets"), 1);

        // 新密碼（用網站同一套 unlock）解得回原文，舊密碼解不開
        let key = vault::unlock(&setup.salt, setup.iterations, &setup.check, "新的密碼 abcdefgh").unwrap().unwrap();
        let mine = secrets_of(&db, "mine");
        assert_eq!(vault::decrypt_text(&key, &mine["a"]).unwrap().as_str(), SECRET);
        assert_eq!(vault::decrypt_text(&key, &mine["b"]).unwrap().as_str(), "PLAINTEXT234567");
        assert!(vault::decrypt_text(&vault::unlock(SALT, vault::ITERATIONS, CHECK, PASSPHRASE).unwrap().unwrap(), &mine["a"]).is_err());
        assert_eq!(secrets_of(&db, "theirs")["d"], CIPHER, "別人的群組不動");
        // Rust 裡的金鑰換成新的
        assert!(vault_restore_wrapped(setup.check.clone(), vault_export_wrapped().unwrap()));

        // 別的裝置先改過：資料庫拒絕，訊息照原樣
        vault_create("第三組密碼 12345678".into());
        let stale = block_on(vault_rewrite_all(connection(), current(&setup.salt, &setup.check, "新的密碼 abcdefgh"), true, Some(CHECK.into()), None));
        assert_eq!(stale.as_deref(), Some(CHANGED_ELSEWHERE));

        // 停用：寫回明文，群組改成沒加密，Rust 裡沒有金鑰
        let disabled = block_on(vault_rewrite_all(connection(), current(&setup.salt, &setup.check, "新的密碼 abcdefgh"), false, Some(setup.check.clone()), Some("esc:v1:ignored".into())));
        assert_eq!(disabled, None);
        assert!(!vault_is_unlocked());
        let sent = db.lock().unwrap().requests.iter().rev().find(|(f, _)| f == "totp_set_vault").unwrap().1.clone();
        assert!(sent.get("escrow").is_none(), "停用時不送備援");
        let mine = secrets_of(&db, "mine");
        assert_eq!(mine["a"], SECRET);
        assert_eq!(mine["b"], "PLAINTEXT234567");
        assert_eq!(db.lock().unwrap().check, None);
    }

    // 設定密碼後加密預設群組；有一筆解不開時整批不送
    #[test]
    fn enable_and_toggle_group() {
        let _serial = serial();
        vault_lock();
        let db = Arc::new(Mutex::new(FakeDb {
            groups: vec![("home".into(), true, false)],
            secrets: BTreeMap::from([("home".into(), BTreeMap::from([("a".into(), SECRET.into())]))]),
            ..Default::default()
        }));
        let connection = || fake_supabase(db.clone());

        assert_eq!(
            block_on(vault_set_group_encrypted(connection(), "home".into(), true, CHECK.into())).as_deref(),
            Some("請先輸入加密密碼解鎖")
        );

        // 舊的資料庫沒有 escrow 參數：改用舊的呼叫方式，設定照樣存好
        db.lock().unwrap().legacy = true;
        let setup = vault_create("新的密碼 abcdefgh".into());
        assert_eq!(block_on(vault_rewrite_all(connection(), None, true, None, Some("esc:v1:kid:epk:iv:ct".into()))), None);
        assert_eq!(calls(&db, "totp_set_vault"), 2);
        db.lock().unwrap().legacy = false;
        assert!(vault_is_unlocked());
        assert_eq!(calls(&db, "group_account_secrets"), 0, "設定密碼時不用讀金鑰");
        assert_eq!(db.lock().unwrap().check.as_deref(), Some(setup.check.as_str()));

        // 拿舊的 check：解鎖的金鑰對不上
        assert_eq!(
            block_on(vault_set_group_encrypted(connection(), "home".into(), true, CHECK.into())).as_deref(),
            Some(CHANGED_ELSEWHERE)
        );

        assert_eq!(block_on(vault_set_group_encrypted(connection(), "home".into(), true, setup.check.clone())), None);
        let key = vault::unlock(&setup.salt, setup.iterations, &setup.check, "新的密碼 abcdefgh").unwrap().unwrap();
        let home = secrets_of(&db, "home");
        assert_eq!(vault::decrypt_text(&key, &home["a"]).unwrap().as_str(), SECRET);
        assert!(db.lock().unwrap().groups[0].2);

        // 群組裡有一筆是網站用別的密碼加密的：解不開，不送出
        db.lock().unwrap().secrets.get_mut("home").unwrap().insert("x".into(), CIPHER.into());
        let before = calls(&db, "group_set_encrypted");
        assert_eq!(
            block_on(vault_set_group_encrypted(connection(), "home".into(), false, setup.check.clone())).as_deref(),
            Some(UNDECRYPTABLE)
        );
        assert_eq!(calls(&db, "group_set_encrypted"), before);

        db.lock().unwrap().secrets.get_mut("home").unwrap().remove("x");
        assert_eq!(block_on(vault_set_group_encrypted(connection(), "home".into(), false, setup.check.clone())), None);
        assert_eq!(secrets_of(&db, "home")["a"], SECRET);
        vault_lock();
    }
}
