// 上傳大頭照、背景圖前的壓縮（Flutter 先解碼、縮小，這裡編成 JPEG）

use securibit_core::photo;

/// RGBA 像素（每像素 4 位元組）編成 JPEG；quality 1～100。
/// 不是 sync：在 flutter_rust_bridge 的執行緒池跑，不會卡住畫面
pub fn photo_encode_jpeg(width: u32, height: u32, rgba: Vec<u8>, quality: u8) -> Result<Vec<u8>, String> {
    photo::encode_jpeg_rgba(width, height, &rgba, quality).map_err(|error| error.to_string())
}
