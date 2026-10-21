// 表單錯誤（同網站 src/lib/totp/validate.ts），訊息一字不差

use crate::secret::{is_valid_secret, normalize_secret};

pub const NAME_REQUIRED: &str = "請輸入名稱";
pub const SECRET_REQUIRED: &str = "請輸入金鑰";
pub const SECRET_FORMAT: &str = "金鑰格式錯誤，只能包含 A-Z 與 2-7（Base32）";

#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct TotpErrors {
    pub name: Option<String>,
    pub secret: Option<String>,
}

fn name_error(name: &str) -> Option<String> {
    // JS 的 trim 與 Dart 的 trim 都去掉 Unicode 空白，Rust 的 trim 也是
    name.trim().is_empty().then(|| NAME_REQUIRED.to_string())
}

/// 名稱與金鑰必填、金鑰需為 Base32
pub fn validate_input(name: &str, secret: &str) -> TotpErrors {
    let secret_error = if normalize_secret(secret).is_empty() {
        Some(SECRET_REQUIRED.to_string())
    } else if !is_valid_secret(secret) {
        Some(SECRET_FORMAT.to_string())
    } else {
        None
    };
    TotpErrors { name: name_error(name), secret: secret_error }
}

/// 編輯時：看不到原本金鑰的人可以留空（代表不修改），看得到的人不能清空（同網站 GroupCodeEditModal）
pub fn validate_edit(name: &str, secret: &str, secret_known: bool) -> TotpErrors {
    let secret_error = if normalize_secret(secret).is_empty() {
        secret_known.then(|| SECRET_REQUIRED.to_string())
    } else if !is_valid_secret(secret) {
        Some(SECRET_FORMAT.to_string())
    } else {
        None
    };
    TotpErrors { name: name_error(name), secret: secret_error }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn messages_match_website() {
        let empty = validate_input("", "");
        assert_eq!(empty.name.as_deref(), Some("請輸入名稱"));
        assert_eq!(empty.secret.as_deref(), Some("請輸入金鑰"));

        let bad = validate_input("a", "abc1");
        assert_eq!(bad.name, None);
        assert_eq!(bad.secret.as_deref(), Some(SECRET_FORMAT));

        assert_eq!(validate_input("a", "jbsw y3dp"), TotpErrors::default());
        assert_eq!(validate_edit("a", "", false), TotpErrors::default());
        assert_eq!(validate_edit("a", "", true).secret.as_deref(), Some("請輸入金鑰"));
        assert_eq!(validate_edit(" ", "x1", false).name.as_deref(), Some("請輸入名稱"));
    }
}
