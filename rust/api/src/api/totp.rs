// 不需要狀態的工具：金鑰格式、表單驗證、otpauth:// 連結、單次產碼（介紹頁的示範與後台用）

use flutter_rust_bridge::frb;
use securibit_core::totp::Algorithm;
use securibit_core::{base32, otpauth, secret, totp, validate};

/// 去除空白與連字號、轉大寫、去掉結尾的 = 補位
#[frb(sync)]
pub fn normalize_secret(secret: String) -> String {
    secret::normalize_secret(&secret)
}

/// 金鑰是否可用（正規化後為 Base32）
#[frb(sync)]
pub fn is_valid_secret(secret: String) -> bool {
    secret::is_valid_secret(&secret)
}

#[frb(sync)]
pub fn base32_encode(bytes: Vec<u8>) -> String {
    base32::encode(&bytes)
}

pub struct Base32Decoded {
    pub bytes: Vec<u8>,
    // 有不合法字元時的訊息（同網站：「不是 Base32 字元：x」）
    pub error: Option<String>,
}

#[frb(sync)]
pub fn base32_decode(input: String) -> Base32Decoded {
    match base32::decode(&input) {
        Ok(bytes) => Base32Decoded { bytes, error: None },
        Err(error) => Base32Decoded { bytes: Vec::new(), error: Some(error.to_string()) },
    }
}

/// 某個時間點的驗證碼；金鑰不合法時是 null。algorithm 是 SHA-1 / SHA-256 / SHA-512
#[frb(sync)]
pub fn totp_generate(secret: String, digits: u32, period: u32, algorithm: String, timestamp_ms: i64) -> Option<String> {
    totp::generate(&secret, digits, period, Algorithm::from_label(&algorithm), timestamp_ms)
}

/// 表單欄位的錯誤訊息（同網站），沒有錯誤的欄位是 null
pub struct TotpFieldErrors {
    pub name: Option<String>,
    pub secret: Option<String>,
}

impl From<validate::TotpErrors> for TotpFieldErrors {
    fn from(value: validate::TotpErrors) -> Self {
        TotpFieldErrors { name: value.name, secret: value.secret }
    }
}

/// 新增：名稱與金鑰必填、金鑰需為 Base32
#[frb(sync)]
pub fn validate_totp_input(name: String, secret: String) -> TotpFieldErrors {
    validate::validate_input(&name, &secret).into()
}

/// 編輯：看不到原本金鑰的人可以留空（代表不修改）
#[frb(sync)]
pub fn validate_totp_edit(name: String, secret: String, secret_known: bool) -> TotpFieldErrors {
    validate::validate_edit(&name, &secret, secret_known).into()
}

/// 「金鑰格式錯誤」的訊息（後台的表單也用）
#[frb(sync)]
pub fn secret_format_message() -> String {
    validate::SECRET_FORMAT.to_string()
}

/// otpauth:// 連結的內容；category 是連結裡的原始值
pub struct OtpauthLink {
    pub name: String,
    pub secret: String,
    pub category: String,
    pub digits: u32,
    pub period: u32,
    // SHA-1 / SHA-256 / SHA-512
    pub algorithm: String,
}

pub struct OtpauthParsed {
    pub link: Option<OtpauthLink>,
    // 錯誤訊息（同網站）
    pub error: Option<String>,
}

#[frb(sync)]
pub fn parse_otpauth(text: String) -> OtpauthParsed {
    match otpauth::parse(&text) {
        Ok(item) => OtpauthParsed {
            link: Some(OtpauthLink {
                name: item.name,
                secret: item.secret,
                category: item.category,
                digits: item.digits,
                period: item.period,
                algorithm: item.algorithm.label().to_string(),
            }),
            error: None,
        },
        Err(message) => OtpauthParsed { link: None, error: Some(message) },
    }
}

#[frb(sync)]
pub fn build_otpauth(link: OtpauthLink) -> String {
    otpauth::build(&otpauth::OtpauthItem {
        name: link.name,
        secret: link.secret,
        category: link.category,
        digits: link.digits,
        period: link.period,
        algorithm: Algorithm::from_label(&link.algorithm),
    })
}
