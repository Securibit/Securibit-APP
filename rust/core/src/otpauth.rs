/*
 * otpauth:// 連結（Key URI Format，各服務綁定用的 QR Code 內容就是這個），同網站 src/lib/totp/otpauth.ts：
 * otpauth://totp/Issuer:account?secret=...&issuer=...&digits=6&period=30&algorithm=SHA1
 */

use percent_encoding::{percent_decode_str, utf8_percent_encode, AsciiSet, NON_ALPHANUMERIC};
use url::Url;

use crate::secret::{is_valid_secret, normalize_secret};
use crate::totp::{Algorithm, DEFAULT_DIGITS, DEFAULT_PERIOD, DIGITS_OPTIONS, PERIOD_OPTIONS};

const INVALID_LINK: &str = "不是有效的 otpauth:// 連結";

/// 解析出來的一筆（category 是連結裡的原始值，類別的整理在 Dart 端做）
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct OtpauthItem {
    pub name: String,
    pub secret: String,
    pub category: String,
    pub digits: u32,
    pub period: u32,
    pub algorithm: Algorithm,
}

/// 組出顯示名稱：label 可能是「Issuer:account」或只有 account，issuer 參數優先。
/// 結果為「Issuer - account」，只有其中一個就用那個
pub fn compose_name(label: &str, issuer_param: &str) -> String {
    let (label_issuer, account) = match label.find(':') {
        Some(i) => (label[..i].trim(), label[i + 1..].trim()),
        None => ("", label.trim()),
    };
    let issuer = if issuer_param.trim().is_empty() { label_issuer } else { issuer_param.trim() };

    if !issuer.is_empty() && !account.is_empty() && issuer != account {
        return format!("{issuer} - {account}");
    }
    if !issuer.is_empty() {
        return issuer.to_string();
    }
    if !account.is_empty() {
        return account.to_string();
    }
    "未命名".to_string()
}

// otpauth 的 algorithm 參數寫作 SHA1 / SHA256 / SHA512
fn to_algorithm(value: Option<&str>) -> Option<Algorithm> {
    let value = match value {
        None | Some("") => return Some(Algorithm::default()),
        Some(v) => v.to_uppercase(),
    };
    let normalized = match value.strip_prefix("SHA-").or_else(|| value.strip_prefix("SHA")) {
        Some(rest) => format!("SHA-{rest}"),
        None => value,
    };
    Algorithm::ALL.into_iter().find(|a| a.label() == normalized)
}

// 同 JS 的 Number()：沒有參數用預設值、空字串是 0、不是數字為 None
fn to_number(value: Option<&str>, fallback: u32) -> Option<f64> {
    let Some(value) = value else { return Some(fallback as f64) };
    let trimmed = value.trim();
    if trimmed.is_empty() {
        return Some(0.0);
    }
    if let Some(hex) = trimmed.strip_prefix("0x").or_else(|| trimmed.strip_prefix("0X")) {
        return i64::from_str_radix(hex, 16).ok().map(|n| n as f64);
    }
    trimmed.parse::<f64>().ok().filter(|n| n.is_finite())
}

fn pick(value: Option<f64>, options: &[u32]) -> Option<u32> {
    let value = value?;
    options.iter().copied().find(|&o| o as f64 == value)
}

pub fn parse(text: &str) -> Result<OtpauthItem, String> {
    let raw = text.trim();
    let url = Url::parse(raw).map_err(|_| INVALID_LINK.to_string())?;
    if !url.scheme().eq_ignore_ascii_case("otpauth") {
        return Err(INVALID_LINK.into());
    }
    let kind = url.host_str().unwrap_or("").to_lowercase();
    if kind == "hotp" {
        return Err("目前只支援 TOTP（時間型）驗證碼，不支援 HOTP（計數型）".into());
    }
    if kind != "totp" {
        return Err(INVALID_LINK.into());
    }

    // 同一個參數出現多次時取第一個（同瀏覽器的 URLSearchParams.get）
    let pairs: Vec<(String, String)> = url.query_pairs().into_owned().collect();
    let param = |key: &str| pairs.iter().find(|(k, _)| k == key).map(|(_, v)| v.as_str());

    let secret = normalize_secret(param("secret").unwrap_or(""));
    if secret.is_empty() {
        return Err("連結裡沒有金鑰（secret）".into());
    }
    if !is_valid_secret(&secret) {
        return Err("連結裡的金鑰不是 Base32 格式".into());
    }

    let digits_text = param("digits");
    let digits = pick(to_number(digits_text, DEFAULT_DIGITS), &DIGITS_OPTIONS)
        .ok_or_else(|| format!("不支援 {} 位數的驗證碼", digits_text.unwrap_or("").trim()))?;

    let period_text = param("period");
    let period = pick(to_number(period_text, DEFAULT_PERIOD), &PERIOD_OPTIONS)
        .ok_or_else(|| format!("不支援 {} 秒的週期", period_text.unwrap_or("").trim()))?;

    let algorithm_text = param("algorithm");
    let algorithm =
        to_algorithm(algorithm_text).ok_or_else(|| format!("不支援 {} 演算法", algorithm_text.unwrap_or("")))?;

    let path = url.path().strip_prefix('/').unwrap_or(url.path());
    let label = match percent_decode_str(path).decode_utf8() {
        Ok(decoded) => decoded.trim().to_string(),
        Err(_) => path.trim().to_string(),
    };
    let name = compose_name(&label, param("issuer").unwrap_or(""));
    // category 不是標準參數，是網站匯出備份時加上的（多個類別用「,」串起來），其他 App 會忽略
    let category = param("category").unwrap_or("").to_string();

    Ok(OtpauthItem { name, secret, category, digits, period, algorithm })
}

// Dart 的 Uri.encodeComponent 保留的字元：A-Z a-z 0-9 - _ . ! ~ * ' ( )
const COMPONENT: &AsciiSet = &NON_ALPHANUMERIC
    .remove(b'-')
    .remove(b'_')
    .remove(b'.')
    .remove(b'!')
    .remove(b'~')
    .remove(b'*')
    .remove(b'\'')
    .remove(b'(')
    .remove(b')');

// Dart 的 Uri.encodeQueryComponent 保留的字元：A-Z a-z 0-9 - _ . ~，空白寫成 +
const QUERY: &AsciiSet = &NON_ALPHANUMERIC.remove(b'-').remove(b'_').remove(b'.').remove(b'~');

fn encode_query(value: &str) -> String {
    value
        .split(' ')
        .map(|part| utf8_percent_encode(part, QUERY).to_string())
        .collect::<Vec<_>>()
        .join("+")
}

/// 產生 otpauth:// 連結（可轉成 QR Code 給其他驗證器 App 掃）
pub fn build(item: &OtpauthItem) -> String {
    let mut query = vec![
        ("secret", normalize_secret(&item.secret)),
        ("algorithm", item.algorithm.label().replace('-', "")),
        ("digits", item.digits.to_string()),
        ("period", item.period.to_string()),
    ];
    if !item.category.is_empty() {
        query.push(("category", item.category.clone()));
    }
    let encoded: Vec<String> = query.iter().map(|(k, v)| format!("{k}={}", encode_query(v))).collect();
    format!("otpauth://totp/{}?{}", utf8_percent_encode(&item.name, COMPONENT), encoded.join("&"))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn ok(uri: &str) -> OtpauthItem {
        parse(uri).unwrap()
    }

    fn err(uri: &str) -> String {
        parse(uri).err().unwrap_or_else(|| "ok".into())
    }

    #[test]
    fn standard_link() {
        let item = ok("otpauth://totp/GitHub:me%40example.com?secret=jbswy3dpehpk3pxp&issuer=GitHub");
        assert_eq!(item.name, "GitHub - me@example.com");
        assert_eq!(item.secret, "JBSWY3DPEHPK3PXP");
        assert_eq!((item.digits, item.period, item.algorithm), (6, 30, Algorithm::Sha1));
        assert_eq!(item.category, "");
    }

    #[test]
    fn advanced_params() {
        let item = ok("otpauth://totp/Acme?secret=JBSWY3DPEHPK3PXP&digits=8&period=60&algorithm=SHA512&category=%E5%B7%A5%E4%BD%9C");
        assert_eq!(item.name, "Acme");
        assert_eq!((item.digits, item.period, item.algorithm), (8, 60, Algorithm::Sha512));
        assert_eq!(item.category, "工作");
        assert_eq!(ok("otpauth://totp/a?secret=JBSWY3DP&algorithm=sha-256").algorithm, Algorithm::Sha256);
        assert_eq!(ok("otpauth://totp/a?secret=JBSWY3DP&digits=8.0").digits, 8);
    }

    #[test]
    fn issuer_param_wins() {
        assert_eq!(ok("otpauth://totp/Old:alice?secret=JBSWY3DP&issuer=New").name, "New - alice");
        assert_eq!(ok("otpauth://totp/alice?secret=JBSWY3DP").name, "alice");
        assert_eq!(ok("otpauth://totp/?secret=JBSWY3DP").name, "未命名");
        assert_eq!(ok("otpauth://totp/Same:Same?secret=JBSWY3DP").name, "Same");
        assert_eq!(ok("otpauth://totp/My%20Bank:alice?secret=JBSWY3DP").name, "My Bank - alice");
    }

    #[test]
    fn error_messages_match_website() {
        assert_eq!(err("https://example.com"), "不是有效的 otpauth:// 連結");
        assert_eq!(err("hello"), "不是有效的 otpauth:// 連結");
        assert_eq!(err("otpauth://hotp/a?secret=JBSWY3DP"), "目前只支援 TOTP（時間型）驗證碼，不支援 HOTP（計數型）");
        assert_eq!(err("otpauth://totp/a"), "連結裡沒有金鑰（secret）");
        assert_eq!(err("otpauth://totp/a?secret=abc1"), "連結裡的金鑰不是 Base32 格式");
        assert_eq!(err("otpauth://totp/a?secret=JBSWY3DP&digits=7"), "不支援 7 位數的驗證碼");
        assert_eq!(err("otpauth://totp/a?secret=JBSWY3DP&digits="), "不支援  位數的驗證碼");
        assert_eq!(err("otpauth://totp/a?secret=JBSWY3DP&period=45"), "不支援 45 秒的週期");
        assert_eq!(err("otpauth://totp/a?secret=JBSWY3DP&algorithm=MD5"), "不支援 MD5 演算法");
    }

    #[test]
    fn build_then_parse() {
        let item = OtpauthItem {
            name: "A B".into(),
            secret: "JBSWY3DPEHPK3PXP".into(),
            category: "工作 個人".into(),
            digits: 8,
            period: 60,
            algorithm: Algorithm::Sha256,
        };
        let uri = build(&item);
        assert_eq!(
            uri,
            "otpauth://totp/A%20B?secret=JBSWY3DPEHPK3PXP&algorithm=SHA256&digits=8&period=60&category=%E5%B7%A5%E4%BD%9C+%E5%80%8B%E4%BA%BA"
        );
        assert_eq!(ok(&uri), item);
    }
}
