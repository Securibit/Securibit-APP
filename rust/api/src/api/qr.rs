// 從圖片讀 QR Code（Linux 用；iOS、Android、macOS 用系統內建的辨識）

use securibit_core::qr_image;
use zeroize::Zeroize;

/// 圖片裡所有 QR Code 的文字（不重複，依找到的順序）；圖片讀得出來但沒有 QR Code 時是空的。
/// 讀不了圖片時回傳給使用者看的訊息（檔案太大、HEIC、壞掉的檔案…）。
/// 不是 sync：在 flutter_rust_bridge 的執行緒池跑，不會卡住畫面
pub fn decode_qr_image(mut bytes: Vec<u8>) -> Result<Vec<String>, String> {
    let result = qr_image::decode_qr_image(&bytes).map_err(|error| error.to_string());
    // 圖片內容等同金鑰，用完歸零
    bytes.zeroize();
    result
}
