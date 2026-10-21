/*
 * 直接呼叫 Supabase 的 PostgREST RPC（同 supabase-dart 的 rpc()），讓金鑰不經過 Dart。
 * TLS 用 rustls（不依賴 OpenSSL），根憑證用內建的 Mozilla 清單，四個平台行為一致。
 * 錯誤訊息比照 Dart 的 errorResult：資料庫的 raise exception 本來就是中文，直接用。
 */

use std::sync::LazyLock;
use std::time::Duration;

use securibit_core::rpc_body::{self, Field};
use securibit_core::sealed::{parse_secrets_json, RawSecrets};
use zeroize::Zeroizing;

use crate::api::secrets::SupabaseConnection;

// 同 Dart 的 core/rpc.dart
const OFFLINE_MESSAGE: &str = "無法連線到伺服器，請檢查網路連線";
const MISSING_FUNCTION: &str = "PGRST202";

pub(crate) struct NetError {
    pub message: String,
    pub offline: bool,
}

static CLIENT: LazyLock<Option<reqwest::Client>> = LazyLock::new(|| {
    reqwest::Client::builder()
        .use_rustls_tls()
        .timeout(Duration::from_secs(20))
        .connect_timeout(Duration::from_secs(10))
        .build()
        .ok()
});

fn offline() -> NetError {
    NetError { message: OFFLINE_MESSAGE.to_string(), offline: true }
}

fn other(message: String) -> NetError {
    NetError { message, offline: false }
}

/// group_account_secrets(gid)：{ 驗證碼 id: 資料庫裡的原始金鑰 }（加密群組是 enc:v1 密文）
pub(crate) async fn group_account_secrets(connection: &SupabaseConnection, gid: &str) -> Result<RawSecrets, NetError> {
    let function = "group_account_secrets";
    let body = rpc(connection, function, serde_json::json!({ "gid": gid })).await?;
    parse_secrets_json(&body).ok_or_else(|| other("發生錯誤：伺服器回傳的金鑰格式不正確".into()))
}

/// my_groups()：我擁有且已開啟加密的群組 id
pub(crate) async fn my_encrypted_groups(connection: &SupabaseConnection) -> Result<Vec<String>, NetError> {
    let body = rpc(connection, "my_groups", serde_json::json!({})).await?;
    let value: serde_json::Value =
        serde_json::from_slice(&body).map_err(|_| other("發生錯誤：伺服器回傳的群組格式不正確".into()))?;
    let list = value.as_array().map(Vec::as_slice).unwrap_or_default();
    Ok(list
        .iter()
        .filter(|g| g.get("is_owner").and_then(|v| v.as_bool()) == Some(true) && g.get("encrypted").and_then(|v| v.as_bool()) == Some(true))
        .filter_map(|g| g.get("id").and_then(|v| v.as_str()).map(str::to_string))
        .collect())
}

/// totp_set_vault(new_vault, secrets, expected_check)：存新的加密設定（null 是停用），並把加密群組的金鑰整批換掉。
/// expected_check 和資料庫目前的不同（別的裝置先改過）時資料庫會拒絕
pub(crate) async fn totp_set_vault(
    connection: &SupabaseConnection,
    new_vault: Option<&str>,
    secrets: &RawSecrets,
    expected_check: Option<&str>,
) -> Result<(), NetError> {
    let body = rpc_body::object(&[
        ("new_vault", new_vault.map_or(Field::Null, Field::Json)),
        ("secrets", Field::Secrets(secrets)),
        ("expected_check", Field::opt_str(expected_check)),
    ]);
    let response = send(connection, "totp_set_vault", body).await?;
    // 回傳 null 代表找不到 profile（同網站 saveVault）
    if response.trim_ascii() == b"null" {
        return Err(other("找不到使用者資料".into()));
    }
    Ok(())
}

/// group_set_encrypted(gid, encrypted, secrets, expected_check)：開關一個群組的加密並換掉它的金鑰
pub(crate) async fn group_set_encrypted(
    connection: &SupabaseConnection,
    gid: &str,
    encrypted: bool,
    secrets: &RawSecrets,
    expected_check: &str,
) -> Result<(), NetError> {
    let body = rpc_body::object(&[
        ("gid", Field::Str(gid)),
        ("encrypted", Field::Bool(encrypted)),
        ("secrets", Field::Secrets(secrets)),
        ("expected_check", Field::Str(expected_check)),
    ]);
    send(connection, "group_set_encrypted", body).await.map(|_| ())
}

async fn rpc(connection: &SupabaseConnection, function: &str, params: serde_json::Value) -> Result<Zeroizing<Vec<u8>>, NetError> {
    send(connection, function, Zeroizing::new(params.to_string().into_bytes())).await
}

/*
 * 送出 RPC。請求的內容可能含金鑰：交給 reqwest 時不複製，送完後連同緩衝區一起歸零
 * （TLS 加密時 rustls 內部的暫存不在這裡的控制範圍）。
 */
async fn send(connection: &SupabaseConnection, function: &str, body: Zeroizing<Vec<u8>>) -> Result<Zeroizing<Vec<u8>>, NetError> {
    let client = CLIENT.as_ref().ok_or_else(|| other("發生錯誤：無法建立連線".into()))?;
    let url = format!("{}/rest/v1/rpc/{function}", connection.url.trim_end_matches('/'));
    let mut response = client
        .post(url)
        .header("apikey", &connection.anon_key)
        .bearer_auth(&connection.access_token)
        .header("Content-Type", "application/json")
        .header("Accept", "application/json")
        .header("User-Agent", &connection.user_agent)
        .body(bytes::Bytes::from_owner(body))
        .send()
        .await
        .map_err(|error| if error.is_builder() { other(format!("發生錯誤：{error}")) } else { offline() })?;

    let status = response.status();
    // 一段一段讀進會歸零的緩衝區，不留下完整的回應副本
    let capacity = response.content_length().unwrap_or(16 * 1024).min(4 * 1024 * 1024) as usize;
    let mut body = Zeroizing::new(Vec::with_capacity(capacity));
    loop {
        match response.chunk().await {
            Ok(Some(chunk)) => append(&mut body, &chunk),
            Ok(None) => break,
            Err(_) => return Err(offline()),
        }
    }
    if status.is_success() {
        return Ok(body);
    }

    // PostgREST 的錯誤：{ code, message, details, hint }
    let json: serde_json::Value = serde_json::from_slice(&body).unwrap_or_default();
    let code = json.get("code").and_then(|v| v.as_str()).unwrap_or("");
    if code == MISSING_FUNCTION {
        return Err(other(format!("資料庫還沒有「{function}」功能，請先更新網站的資料庫")));
    }
    let message = json
        .get("message")
        .and_then(|v| v.as_str())
        .filter(|m| !m.is_empty())
        .map(str::to_string)
        .unwrap_or_else(|| format!("請求失敗（{}）", status.as_u16()));
    Err(other(message))
}

// 放不下時自己換一塊更大的緩衝區，舊的那塊由 Zeroizing 歸零（Vec 自己擴充不會清掉舊的記憶體）
fn append(body: &mut Zeroizing<Vec<u8>>, chunk: &[u8]) {
    if body.len() + chunk.len() > body.capacity() {
        let mut bigger = Zeroizing::new(Vec::with_capacity((body.len() + chunk.len()).max(body.capacity() * 2)));
        bigger.extend_from_slice(body);
        *body = bigger;
    }
    body.extend_from_slice(chunk);
}
