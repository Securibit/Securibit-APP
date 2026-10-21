// 標準 base64（含 = 補位），同瀏覽器的 btoa / atob 與 Dart 的 base64
use base64::engine::general_purpose::STANDARD;
use base64::Engine;

pub(crate) fn encode(bytes: &[u8]) -> String {
    STANDARD.encode(bytes)
}

pub(crate) fn decode(value: &str) -> Option<Vec<u8>> {
    STANDARD.decode(value.trim()).ok()
}
