// RFC 4648 Base32（TOTP 金鑰的標準格式），不輸出結尾的 = 補位（同網站 src/lib/totp/base32.ts）

const ALPHABET: &[u8; 32] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";

/// 不是 Base32 字元時的錯誤，訊息同網站
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Base32Error(pub char);

impl std::fmt::Display for Base32Error {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "不是 Base32 字元：{}", self.0)
    }
}

impl std::error::Error for Base32Error {}

pub fn encode(bytes: &[u8]) -> String {
    let mut bits = 0u32;
    let mut value = 0u64;
    let mut output = String::with_capacity(bytes.len() * 8 / 5 + 1);
    for &byte in bytes {
        value = ((value << 8) | byte as u64) & 0xFFFF_FFFF;
        bits += 8;
        while bits >= 5 {
            output.push(ALPHABET[((value >> (bits - 5)) & 31) as usize] as char);
            bits -= 5;
        }
    }
    if bits > 0 {
        output.push(ALPHABET[((value << (5 - bits)) & 31) as usize] as char);
    }
    output
}

/// 傳入前請先 normalize_secret（大寫、無空白、無 =）
pub fn decode(input: &str) -> Result<Vec<u8>, Base32Error> {
    let mut bits = 0u32;
    let mut value = 0u64;
    let mut output = Vec::with_capacity(input.len() * 5 / 8);
    for ch in input.chars() {
        let index = ALPHABET.iter().position(|&a| a as char == ch).ok_or(Base32Error(ch))?;
        value = ((value << 5) | index as u64) & 0xFFFF_FFFF;
        bits += 5;
        if bits >= 8 {
            output.push(((value >> (bits - 8)) & 255) as u8);
            bits -= 8;
        }
    }
    Ok(output)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rfc4648_without_padding() {
        assert_eq!(encode(b""), "");
        assert_eq!(encode(b"f"), "MY");
        assert_eq!(encode(b"fo"), "MZXQ");
        assert_eq!(encode(b"foo"), "MZXW6");
        assert_eq!(encode(b"foob"), "MZXW6YQ");
        assert_eq!(encode(b"fooba"), "MZXW6YTB");
        assert_eq!(encode(b"foobar"), "MZXW6YTBOI");
        assert_eq!(decode("MZXW6YTBOI").unwrap(), b"foobar");
        assert_eq!(decode("MZ1"), Err(Base32Error('1')));
        assert_eq!(decode("MZ1").unwrap_err().to_string(), "不是 Base32 字元：1");
    }

    #[test]
    fn round_trip() {
        let bytes: Vec<u8> = (0..=255).collect();
        assert_eq!(decode(&encode(&bytes)).unwrap(), bytes);
    }
}
