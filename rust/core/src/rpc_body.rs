/*
 * 送給 Supabase RPC 的 JSON（含金鑰時用）：直接寫進預先配置好大小、會歸零的緩衝區，
 * 不經過 serde_json 的 Value（裡面的字串副本不會歸零），也不會因為緩衝區變大而在舊的記憶體留下副本。
 */

use zeroize::Zeroizing;

use crate::sealed::RawSecrets;

/// 欄位的值
pub enum Field<'a> {
    Null,
    Bool(bool),
    Str(&'a str),
    // 已經是 JSON 的值（例如加密設定的物件；不含金鑰）
    Json(&'a str),
    // { 驗證碼 id: 金鑰 }
    Secrets(&'a RawSecrets),
}

impl<'a> Field<'a> {
    pub fn opt_str(value: Option<&'a str>) -> Field<'a> {
        value.map_or(Field::Null, Field::Str)
    }

    // 寫出來最多幾個位元組（字串每個位元組跳脫後最多 6 個）
    fn max_len(&self) -> usize {
        match self {
            Field::Null | Field::Bool(_) => 5,
            Field::Str(s) => quoted_max(s),
            Field::Json(s) => s.len(),
            Field::Secrets(map) => 2 + map.iter().map(|(k, v)| quoted_max(k) + 1 + quoted_max(v) + 1).sum::<usize>(),
        }
    }

    fn write(&self, out: &mut String) {
        match self {
            Field::Null => out.push_str("null"),
            Field::Bool(b) => out.push_str(if *b { "true" } else { "false" }),
            Field::Str(s) => write_str(out, s),
            Field::Json(s) => out.push_str(s),
            Field::Secrets(map) => {
                out.push('{');
                for (i, (k, v)) in map.iter().enumerate() {
                    if i > 0 {
                        out.push(',');
                    }
                    write_str(out, k);
                    out.push(':');
                    write_str(out, v);
                }
                out.push('}');
            }
        }
    }
}

fn quoted_max(s: &str) -> usize {
    s.len() * 6 + 2
}

/// 組出 { "名稱": 值, … }
pub fn object(fields: &[(&str, Field)]) -> Zeroizing<Vec<u8>> {
    let capacity = 2 + fields.iter().map(|(k, v)| quoted_max(k) + 1 + v.max_len() + 1).sum::<usize>();
    let mut out = Zeroizing::new(String::with_capacity(capacity));
    out.push('{');
    for (i, (k, v)) in fields.iter().enumerate() {
        if i > 0 {
            out.push(',');
        }
        write_str(&mut out, k);
        out.push(':');
        v.write(&mut out);
    }
    out.push('}');
    debug_assert!(out.len() <= capacity);
    // String 轉成 Vec 不會複製
    let bytes = std::mem::take(&mut *out).into_bytes();
    Zeroizing::new(bytes)
}

// JSON 字串：引號、反斜線與控制字元跳脫，其餘原樣（UTF-8）
fn write_str(out: &mut String, s: &str) {
    const HEX: &[u8; 16] = b"0123456789abcdef";
    out.push('"');
    for c in s.chars() {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            c if (c as u32) < 0x20 => {
                out.push_str("\\u00");
                out.push(HEX[(c as usize) >> 4] as char);
                out.push(HEX[(c as usize) & 0xf] as char);
            }
            c => out.push(c),
        }
    }
    out.push('"');
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn writes_valid_json() {
        let secrets: RawSecrets = [
            ("a".to_string(), Zeroizing::new("JBSWY3DP".to_string())),
            ("b\"".to_string(), Zeroizing::new("中文\\\n\u{1}x".to_string())),
        ]
        .into_iter()
        .collect();
        let body = object(&[
            ("gid", Field::Str("g-1")),
            ("encrypted", Field::Bool(true)),
            ("new_vault", Field::Json(r#"{"v":1}"#)),
            ("expected_check", Field::opt_str(None)),
            ("secrets", Field::Secrets(&secrets)),
        ]);
        let value: serde_json::Value = serde_json::from_slice(&body).unwrap();
        assert_eq!(
            value,
            serde_json::json!({
                "gid": "g-1",
                "encrypted": true,
                "new_vault": { "v": 1 },
                "expected_check": null,
                "secrets": { "a": "JBSWY3DP", "b\"": "中文\\\n\u{1}x" },
            })
        );
        assert_eq!(object(&[]).as_slice(), b"{}");
    }
}
