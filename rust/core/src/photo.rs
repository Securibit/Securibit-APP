/*
 * 上傳大頭照、背景圖前的壓縮：網站的上傳上限約 4.5 MB（Vercel 的請求大小），太大的圖片在裝置上先縮小再傳。
 * 解碼由 Flutter 做（各平台都讀得到的格式，含 iPhone 的 HEIC），這裡只把縮好的 RGBA 像素編成 JPEG；
 * 伺服器之後會再轉成 WebP、去掉中繼資料。
 */

use image::codecs::jpeg::JpegEncoder;
use image::{ExtendedColorType, ImageEncoder};

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum PhotoError {
    // 像素數量和寬高對不上
    Size,
    Encode,
}

impl std::fmt::Display for PhotoError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(match self {
            PhotoError::Size => "圖片的大小不正確",
            PhotoError::Encode => "無法壓縮圖片",
        })
    }
}

impl std::error::Error for PhotoError {}

/// RGBA（每像素 4 位元組）編成 JPEG；透明的地方疊在白色上（JPEG 沒有透明）
pub fn encode_jpeg_rgba(width: u32, height: u32, rgba: &[u8], quality: u8) -> Result<Vec<u8>, PhotoError> {
    let pixels = (width as usize).checked_mul(height as usize).ok_or(PhotoError::Size)?;
    if width == 0 || height == 0 || rgba.len() != pixels * 4 {
        return Err(PhotoError::Size);
    }
    let mut rgb = Vec::with_capacity(pixels * 3);
    for px in rgba.chunks_exact(4) {
        let alpha = px[3] as u32;
        for &channel in &px[..3] {
            rgb.push(((channel as u32 * alpha + 255 * (255 - alpha)) / 255) as u8);
        }
    }
    let mut out = Vec::new();
    JpegEncoder::new_with_quality(&mut out, quality.clamp(1, 100))
        .write_image(&rgb, width, height, ExtendedColorType::Rgb8)
        .map_err(|_| PhotoError::Encode)?;
    Ok(out)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn encodes_jpeg() {
        let (w, h) = (64u32, 48u32);
        let rgba: Vec<u8> = (0..w * h).flat_map(|i| [(i % 256) as u8, 128, 64, 255]).collect();
        let jpeg = encode_jpeg_rgba(w, h, &rgba, 85).unwrap();
        assert_eq!(&jpeg[..2], &[0xff, 0xd8]);
        let back = image::load_from_memory(&jpeg).unwrap();
        assert_eq!((back.width(), back.height()), (w, h));
    }

    #[test]
    fn rejects_wrong_size() {
        assert_eq!(encode_jpeg_rgba(2, 2, &[0; 15], 85), Err(PhotoError::Size));
        assert_eq!(encode_jpeg_rgba(0, 2, &[], 85), Err(PhotoError::Size));
    }

    // 透明疊在白色上
    #[test]
    fn transparent_becomes_white() {
        let jpeg = encode_jpeg_rgba(8, 8, &[0u8; 8 * 8 * 4], 95).unwrap();
        let back = image::load_from_memory(&jpeg).unwrap().to_rgb8();
        assert!(back.pixels().all(|p| p.0.iter().all(|&c| c > 245)));
    }
}
