/*
 * 驗證碼的金鑰：從伺服器取得、放進記憶體、產碼、顯示或複製時才取出、清掉。
 *
 * 正常使用時金鑰不經過 Dart：group_account_secrets() 由這裡直接連 Supabase 取得（Dart 只給網址、anon key 與登入 token），
 * 解密（加密群組）、產碼都在這裡做，Dart 只拿到驗證碼與「有沒有金鑰、格式對不對」。
 * 離線快取的金鑰用這台裝置的金鑰封起來，Dart 只存密文。
 */

use std::collections::{BTreeMap, HashMap};

use flutter_rust_bridge::frb;
use securibit_core::sealed::{self, RawSecrets};
use securibit_core::store::{self, Otp};
use securibit_core::totp::Algorithm;
use securibit_core::vault::VaultKey;
use zeroize::Zeroizing;

use crate::net;
use crate::state::state;

/// 一筆金鑰的公開資訊（不含金鑰本身）
pub struct SecretMeta {
    pub id: String,
    // 格式正確（解不開的加密金鑰是 false，畫面顯示「金鑰錯誤」）
    pub valid: bool,
}

fn metas(list: Vec<store::SecretMeta>) -> Vec<SecretMeta> {
    list.into_iter().map(|m| SecretMeta { id: m.id, valid: m.valid }).collect()
}

/// 連 Supabase 需要的資訊（anon key 本來就是公開的；token 是目前登入的 access token）
pub struct SupabaseConnection {
    pub url: String,
    pub anon_key: String,
    pub access_token: String,
    pub user_agent: String,
}

pub struct SecretsFetch {
    // 成功時放進記憶體的金鑰（封存中是空的）
    pub metas: Vec<SecretMeta>,
    // 封起來給離線快取存的密文
    pub cache: Option<String>,
    // 失敗時給使用者看的訊息
    pub error: Option<String>,
    // 連不上伺服器（可以改用離線快取）
    pub offline: bool,
    // App 鎖定中，金鑰沒有放進記憶體（解鎖後要重新讀取）
    pub sealed: bool,
}

// ---------- 這台裝置的金鑰 ----------

/// 交給 Rust 這台裝置的金鑰（從系統安全儲存讀出來的 base64）；格式不對回傳 false
#[frb(sync)]
pub fn device_key_install(key_base64: String) -> bool {
    use base64::engine::general_purpose::STANDARD;
    use base64::Engine;
    let key_base64 = Zeroizing::new(key_base64);
    let Ok(bytes) = STANDARD.decode(key_base64.trim()) else { return false };
    let bytes = Zeroizing::new(bytes);
    match VaultKey::from_bytes(&bytes) {
        Some(key) => {
            state().device = Some(key);
            true
        }
        None => false,
    }
}

/// 第一次使用：產生新的裝置金鑰並開始使用，回傳 base64 讓 Dart 存進系統安全儲存
#[frb(sync)]
pub fn device_key_generate() -> String {
    use base64::engine::general_purpose::STANDARD;
    use base64::Engine;
    let key = VaultKey::random();
    let encoded = STANDARD.encode(key.as_bytes());
    state().device = Some(key);
    encoded
}

// ---------- 取得與還原 ----------

/*
 * scope 是記憶體裡的一格（每個畫面各用各的，例如主畫面的某個群組、選單列的某個群組），
 * 畫面關掉時清掉自己那一格，不會影響別的畫面。
 */
fn put(scope: &str, encrypted: bool, raw: RawSecrets) -> Option<Vec<SecretMeta>> {
    let mut state = state();
    let key = if encrypted { state.vault.clone() } else { None };
    state.store.put_group(scope, encrypted, raw, key.as_ref()).map(metas)
}

/// 取得群組 gid 裡我有「查看金鑰」的全部金鑰（會在網站記一筆「查看金鑰」紀錄），放進記憶體的 scope
pub async fn secrets_fetch(connection: SupabaseConnection, gid: String, scope: String, encrypted: bool) -> SecretsFetch {
    let fail = |error: String, offline: bool| SecretsFetch { metas: Vec::new(), cache: None, error: Some(error), offline, sealed: false };
    if state().store.is_sealed() {
        return SecretsFetch { metas: Vec::new(), cache: None, error: None, offline: false, sealed: true };
    }
    let raw = match net::group_account_secrets(&connection, &gid).await {
        Ok(raw) => raw,
        Err(error) => return fail(error.message, error.offline),
    };
    let cache = sealed::seal(state().device_key(), &raw);
    match put(&scope, encrypted, raw) {
        Some(metas) => SecretsFetch { metas, cache: Some(cache), error: None, offline: false, sealed: false },
        None => SecretsFetch { metas: Vec::new(), cache: Some(cache), error: None, offline: false, sealed: true },
    }
}

/// 從離線快取的密文還原；解不開（換過裝置金鑰、資料損毀）或封存中回傳 null
#[frb(sync)]
pub fn secrets_restore(scope: String, encrypted: bool, cache: String) -> Option<Vec<SecretMeta>> {
    let raw = {
        let mut state = state();
        if state.store.is_sealed() {
            return None;
        }
        sealed::open(state.device_key(), &cache).ok()?
    };
    put(&scope, encrypted, raw)
}

/// 已經在 Dart 手上的金鑰（後台管理員查看別人的 2FA）也放進來，讓產碼走同一條路；不是加密群組
#[frb(sync)]
pub fn secrets_put(scope: String, raw: HashMap<String, String>) -> Option<Vec<SecretMeta>> {
    let raw: RawSecrets = raw.into_iter().map(|(k, v)| (k, Zeroizing::new(v))).collect::<BTreeMap<_, _>>();
    put(&scope, false, raw)
}

/// 舊版離線快取（改用 Rust 之前直接存原始金鑰）轉成封起來的密文，只在升級後第一次讀取時用
#[frb(sync)]
pub fn secrets_seal_legacy(raw: HashMap<String, String>) -> String {
    let raw: RawSecrets = raw.into_iter().map(|(k, v)| (k, Zeroizing::new(v))).collect::<BTreeMap<_, _>>();
    sealed::seal(state().device_key(), &raw)
}

// ---------- 產碼與取出 ----------

pub enum OtpCodeState {
    // 沒有這筆金鑰
    Missing,
    // 金鑰格式錯誤
    Invalid,
    Ready,
}

pub struct OtpCodes {
    pub state: OtpCodeState,
    pub code: Option<String>,
    pub next: Option<String>,
}

/// 第 counter 個週期與下一個週期的驗證碼（counter = 時間 / 週期）
#[frb(sync)]
pub fn secrets_otp(scope: String, id: String, digits: u32, algorithm: String, counter: i64) -> OtpCodes {
    match state().store.otp(&scope, &id, digits, Algorithm::from_label(&algorithm), counter) {
        Otp::Missing => OtpCodes { state: OtpCodeState::Missing, code: None, next: None },
        Otp::Invalid => OtpCodes { state: OtpCodeState::Invalid, code: None, next: None },
        Otp::Ready { code, next } => OtpCodes { state: OtpCodeState::Ready, code: Some(code), next: Some(next) },
    }
}

/// 使用者按了顯示、複製或編輯時才取出（正規化後的）金鑰；沒有或格式錯誤是 null
#[frb(sync)]
pub fn secrets_reveal(scope: String, id: String) -> Option<String> {
    state().store.reveal(&scope, &id).map(|secret| secret.as_str().to_string())
}

// ---------- 清掉 ----------

/// 刪掉一筆驗證碼
#[frb(sync)]
pub fn secrets_remove(scope: String, id: String) {
    state().store.remove(&scope, &id);
}

#[frb(sync)]
pub fn secrets_clear_scope(scope: String) {
    state().store.clear_group(&scope);
}

/// 登出：清掉全部金鑰與加密群組的金鑰
#[frb(sync)]
pub fn secrets_clear_all() {
    let mut state = state();
    state.store.clear_all();
    state.vault = None;
}

/// App 鎖定：清掉全部金鑰，解鎖前不再接受新的（加密群組的金鑰保留，解鎖後不用重新輸入密碼）
#[frb(sync)]
pub fn secrets_seal() {
    state().store.seal();
}

#[frb(sync)]
pub fn secrets_unseal() {
    state().store.unseal();
}

#[frb(sync)]
pub fn secrets_is_sealed() -> bool {
    state().store.is_sealed()
}
