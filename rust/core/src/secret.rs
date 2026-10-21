// 金鑰的正規化與檢查（同網站 src/lib/totp/crud.ts）

/// 去除空白與連字號、轉大寫、去掉結尾的 = 補位（許多金鑰是小寫或分組顯示）
///
/// 空白的定義同 JS / Dart 正規式的 `\s`（含全形空白、不換行空白等）
pub fn normalize_secret(secret: &str) -> String {
    let upper: String = secret
        .chars()
        .filter(|&c| c != '-' && !is_js_whitespace(c))
        .collect::<String>()
        .to_uppercase();
    upper.trim_end_matches('=').to_string()
}

/// `^[A-Z2-7]+=*$`
pub fn is_base32(input: &str) -> bool {
    let body = input.trim_end_matches('=');
    !body.is_empty() && body.bytes().all(|b| b.is_ascii_uppercase() || (b'2'..=b'7').contains(&b))
}

/// 金鑰是否可用（正規化後為 Base32）
pub fn is_valid_secret(secret: &str) -> bool {
    is_base32(&normalize_secret(secret))
}

// ECMAScript 的 WhiteSpace + LineTerminator（Dart 的 RegExp 也是這一組）
fn is_js_whitespace(c: char) -> bool {
    matches!(
        c,
        '\u{0009}'
            | '\u{000A}'
            | '\u{000B}'
            | '\u{000C}'
            | '\u{000D}'
            | '\u{0020}'
            | '\u{00A0}'
            | '\u{1680}'
            | '\u{2000}'..='\u{200A}'
                | '\u{2028}'
                | '\u{2029}'
                | '\u{202F}'
                | '\u{205F}'
                | '\u{3000}'
                | '\u{FEFF}'
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn normalize() {
        assert_eq!(normalize_secret(" jbsw-y3dp ehpk 3pxp=="), "JBSWY3DPEHPK3PXP");
        assert_eq!(normalize_secret("jbsw\u{3000}y3dp\t\n"), "JBSWY3DP");
        // 只去掉結尾的 =
        assert_eq!(normalize_secret("AB=CD=="), "AB=CD");
    }

    #[test]
    fn base32_check() {
        assert!(is_valid_secret("JBSWY3DPEHPK3PXP"));
        assert!(is_valid_secret("jbsw y3dp"));
        assert!(!is_valid_secret("JBSWY3DPEHPK3PX1"));
        assert!(!is_valid_secret("JBSWY3DP0"));
        assert!(!is_valid_secret(""));
        assert!(!is_valid_secret("===="));
        assert!(!is_valid_secret("AB=CD"));
        assert!(is_base32("AB=="));
        assert!(!is_base32("=="));
    }
}
