/*
 * 從圖片讀 QR Code（匯入驗證碼時選截圖）。iOS、Android、macOS 用系統內建的辨識（mobile_scanner），
 * Linux 沒有，改用這裡：image 解碼 PNG／JPEG／WebP／GIF／BMP，rqrr 找 QR Code，全部是純 Rust。
 *
 * rqrr 比系統的辨識挑剔，所以先整理圖片再交給它：
 * - 合併透明（透明背景的 QR Code 圖片疊在白底上，不然透明的地方會變黑）、轉灰階
 * - 大圖先縮到長邊 1800 px（截圖的模組夠大，縮小後比較快，也比較不會被雜訊干擾）
 * - 讀不到時換尺寸：大圖試 1000 px，再把 3000 px 的圖切成重疊的區塊（照片裡很小的 QR Code）；小圖放大
 * - 每個尺寸各試：原圖、反色（深色模式常見的白碼黑底）、Otsu 二值化、二值化後反色
 * - 二值化後黑白交錯得像雜訊的區塊先塗白（照片的材質會讓 rqrr 慢到幾十秒）
 * - 有任何一種讀到就停；5 秒後不再開始新的嘗試，8 秒還沒結束就回報逾時（辨識在另一條執行緒，不會一直卡住）
 *
 * 圖片內容等同金鑰（otpauth:// 連結），自己配置的像素緩衝用完歸零（rqrr 與 image 內部的暫存無法歸零）。
 */

use std::panic::{catch_unwind, AssertUnwindSafe};
use std::sync::mpsc;
use std::time::{Duration, Instant};

use image::imageops::{self, FilterType};
use image::{DynamicImage, ImageBuffer, ImageError, ImageReader, Limits, Luma};
use zeroize::{Zeroize, Zeroizing};

/// 檔案大小上限（截圖不會這麼大，太大的多半是相機照片或選錯檔案）
pub const MAX_FILE_BYTES: usize = 20 * 1024 * 1024;
// 解碼時的尺寸與記憶體上限（避免小檔案解開變成巨大的圖）
const MAX_DIMENSION: u32 = 16_384;
const MAX_DECODE_ALLOC: u64 = 256 * 1024 * 1024;
// 第一次辨識的長邊
const BASE_LONG_SIDE: u32 = 1800;
// 大圖讀不到時，再試更小的尺寸與更清楚的尺寸（更清楚的切成區塊，rqrr 的時間大約跟像素數的平方成正比）
const SMALL_LONG_SIDE: u32 = 1000;
const DETAIL_LONG_SIDE: u32 = 3000;
// 區塊大小與間距（重疊 400 px，比這大的 QR Code 在縮小的圖就讀得到）
const TILE: u32 = 1200;
const TILE_STRIDE: u32 = 800;
// 小圖放大到大約這個長邊（整數倍、最多 8 倍）
const UPSCALE_TARGET: u32 = 1400;
// 二值化後，每個區塊裡相鄰像素黑白不同的比例超過這個就當成雜訊塗白
// （雜訊接近 0.5；QR Code 每個模組至少 2 px 時不會超過 0.25）
const NOISE_TILE: usize = 32;
const MAX_TRANSITION_DENSITY: f64 = 0.3;
// 第一次以外的嘗試要在這段時間內開始
const TIME_BUDGET: Duration = Duration::from_secs(5);
// 超過這段時間就不等了（rqrr 沒辦法中途停下，正在跑的那次嘗試會在背景跑完）
const HARD_LIMIT: Duration = Duration::from_secs(8);

/// 讀不了圖片的原因；訊息給使用者看
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum QrImageError {
    Empty,
    TooLarge,
    Heic,
    UnsupportedFormat,
    TooManyPixels,
    Corrupt,
    Timeout,
}

impl std::fmt::Display for QrImageError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(match self {
            QrImageError::Empty => "檔案是空的，請重新選擇圖片。",
            QrImageError::TooLarge => "圖片超過 20 MB，請改用較小的截圖。",
            QrImageError::Heic => "不支援 HEIC／HEIF 圖片（iPhone 照片的格式），請先轉成 PNG 或 JPG 再試一次。",
            QrImageError::UnsupportedFormat => "不支援這種圖片格式，請改用 PNG、JPG、WebP、GIF 或 BMP。",
            QrImageError::TooManyPixels => "圖片尺寸太大，請改用較小的截圖。",
            QrImageError::Corrupt => "圖片已損壞或無法讀取，請改用 PNG 或 JPG 截圖。",
            QrImageError::Timeout => "辨識太久，請把 QR Code 的部分裁切出來，或改用清楚一點的截圖。",
        })
    }
}

impl std::error::Error for QrImageError {}

/// 圖片裡所有 QR Code 的文字（依找到的順序、不重複）；讀得出圖片但找不到 QR Code 時是空的
pub fn decode_qr_image(bytes: &[u8]) -> Result<Vec<String>, QrImageError> {
    decode_within(bytes, TIME_BUDGET, HARD_LIMIT)
}

fn decode_within(bytes: &[u8], budget: Duration, hard_limit: Duration) -> Result<Vec<String>, QrImageError> {
    let grey = decode_grey(bytes)?;
    let started = Instant::now();
    let (sender, receiver) = mpsc::channel();
    let spawned = std::thread::Builder::new().name("qr-image".into()).spawn(move || {
        let _ = sender.send(scan_all(&grey, started + budget));
    });
    if spawned.is_err() {
        // 開不了執行緒（幾乎不會發生）時沒辦法逾時，只好直接辨識
        return Ok(scan_all(&decode_grey(bytes)?, started + budget));
    }
    match receiver.recv_timeout(hard_limit.saturating_sub(started.elapsed())) {
        Ok(found) => Ok(found),
        Err(mpsc::RecvTimeoutError::Timeout) => Err(QrImageError::Timeout),
        // 辨識的執行緒當掉了：當作找不到
        Err(mpsc::RecvTimeoutError::Disconnected) => Ok(Vec::new()),
    }
}

// ---------- 解碼 ----------

/// 灰階圖片（0 是黑、255 是白），緩衝用完歸零
struct Grey {
    width: u32,
    height: u32,
    data: Zeroizing<Vec<u8>>,
}

impl Grey {
    fn long_side(&self) -> u32 {
        self.width.max(self.height)
    }

    fn view(&self) -> ImageBuffer<Luma<u8>, &[u8]> {
        ImageBuffer::from_raw(self.width, self.height, &self.data[..]).expect("灰階緩衝大小與尺寸相符")
    }
}

fn decode_grey(bytes: &[u8]) -> Result<Grey, QrImageError> {
    if bytes.is_empty() {
        return Err(QrImageError::Empty);
    }
    if bytes.len() > MAX_FILE_BYTES {
        return Err(QrImageError::TooLarge);
    }
    if let Some(error) = unsupported_container(bytes) {
        return Err(error);
    }

    let mut reader = ImageReader::new(std::io::Cursor::new(bytes))
        .with_guessed_format()
        .map_err(|_| QrImageError::Corrupt)?;
    if reader.format().is_none() {
        return Err(QrImageError::UnsupportedFormat);
    }
    let mut limits = Limits::default();
    limits.max_image_width = Some(MAX_DIMENSION);
    limits.max_image_height = Some(MAX_DIMENSION);
    limits.max_alloc = Some(MAX_DECODE_ALLOC);
    reader.limits(limits);

    // GIF 只取第一個畫格
    let image = reader.decode().map_err(|error| match error {
        ImageError::Unsupported(_) => QrImageError::UnsupportedFormat,
        ImageError::Limits(_) => QrImageError::TooManyPixels,
        _ => QrImageError::Corrupt,
    })?;
    if image.width() == 0 || image.height() == 0 {
        return Err(QrImageError::Corrupt);
    }
    Ok(to_grey(image))
}

/// image 認不得、但常被選到的格式：HEIC／HEIF（iPhone 照片）與 AVIF，用 ISO BMFF 的 ftyp 判斷
fn unsupported_container(bytes: &[u8]) -> Option<QrImageError> {
    if bytes.len() < 12 || &bytes[4..8] != b"ftyp" {
        return None;
    }
    match &bytes[8..12] {
        b"heic" | b"heix" | b"heim" | b"heis" | b"hevc" | b"hevx" | b"hevm" | b"hevs" | b"mif1" | b"msf1" => {
            Some(QrImageError::Heic)
        }
        b"avif" | b"avis" => Some(QrImageError::UnsupportedFormat),
        _ => None,
    }
}

/// 轉灰階；有透明度的圖片先疊在白底上
fn to_grey(image: DynamicImage) -> Grey {
    let (width, height) = (image.width(), image.height());
    let data = if image.color().has_alpha() {
        let la = Zeroizing::new(image.to_luma_alpha8().into_raw());
        la.as_chunks::<2>()
            .0
            .iter()
            .map(|&[l, a]| {
                let (l, a) = (l as u32, a as u32);
                ((l * a + 255 * (255 - a) + 127) / 255) as u8
            })
            .collect()
    } else {
        image.to_luma8().into_raw()
    };
    image.into_bytes().zeroize();
    Grey { width, height, data: Zeroizing::new(data) }
}

/// 縮放到指定的長邊：縮小用平均（thumbnail），放大用最近鄰（保持模組的邊緣清楚）
fn resized(src: &Grey, long_side: u32) -> Grey {
    let long = src.long_side() as u64;
    let scale = |side: u32| ((side as u64 * long_side as u64 + long / 2) / long).max(1) as u32;
    let (width, height) = (scale(src.width), scale(src.height));
    let out = if long_side < src.long_side() {
        imageops::thumbnail(&src.view(), width, height)
    } else {
        imageops::resize(&src.view(), width, height, FilterType::Nearest)
    };
    Grey { width, height, data: Zeroizing::new(out.into_raw()) }
}

// ---------- 辨識 ----------

#[derive(Debug, Clone, Copy)]
enum Filter {
    // rqrr 自己的局部門檻
    Plain,
    // 白碼黑底
    Inverted,
    // 整張圖用同一個門檻（Otsu），對比低或背景有漸層時有幫助
    Binarized,
    BinarizedInverted,
}

const FILTERS: [Filter; 4] = [Filter::Plain, Filter::Inverted, Filter::Binarized, Filter::BinarizedInverted];

/// 一次嘗試的尺寸：縮放到某個長邊，整張或切成重疊的區塊
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct Pass {
    long_side: u32,
    tiled: bool,
}

/// 依序試各種尺寸與處理，有任何一種讀到就回傳（同一種處理的所有區塊都會跑完，才不會漏掉其他 QR Code）
fn scan_all(grey: &Grey, deadline: Instant) -> Vec<String> {
    let mut first = true;
    let mut out_of_time = || {
        let late = !first && Instant::now() >= deadline;
        first = false;
        late
    };
    for pass in passes(grey.long_side()) {
        let owned;
        let image = if pass.long_side == grey.long_side() {
            grey
        } else {
            owned = resized(grey, pass.long_side);
            &owned
        };
        let regions = if pass.tiled {
            tiles(image.width, image.height)
        } else {
            vec![(0, 0, image.width, image.height)]
        };
        for filter in FILTERS {
            let mut found: Vec<String> = Vec::new();
            for &(x, y, w, h) in &regions {
                if out_of_time() {
                    return found;
                }
                let cropped;
                let region = if pass.tiled {
                    cropped = crop(image, x, y, w, h);
                    &cropped
                } else {
                    image
                };
                let threshold = otsu_threshold(&region.data);
                // rqrr 遇到奇怪的圖時不應該讓整個匯入失敗，當作這次沒讀到
                for content in catch_unwind(AssertUnwindSafe(|| scan(region, filter, threshold))).unwrap_or_default() {
                    if !found.contains(&content) {
                        found.push(content);
                    }
                }
            }
            if !found.is_empty() {
                return found;
            }
        }
    }
    Vec::new()
}

/// 要試的尺寸（第一個是主要尺寸）
fn passes(long: u32) -> Vec<Pass> {
    let whole = |long_side| Pass { long_side, tiled: false };
    let mut list = vec![whole(long.min(BASE_LONG_SIDE))];
    if long > BASE_LONG_SIDE {
        list.push(whole(SMALL_LONG_SIDE));
        list.push(Pass { long_side: long.min(DETAIL_LONG_SIDE), tiled: true });
    } else if long < SMALL_LONG_SIDE {
        let factor = UPSCALE_TARGET.div_ceil(long).clamp(2, 8);
        list.push(whole(long * factor));
    } else {
        list.push(whole(long / 2));
    }
    list
}

/// 切成重疊的區塊（x, y, 寬, 高），最後一塊貼齊右邊與下面
fn tiles(width: u32, height: u32) -> Vec<(u32, u32, u32, u32)> {
    let starts = |len: u32| {
        if len <= TILE {
            return vec![0];
        }
        let mut list: Vec<u32> = (0..len - TILE).step_by(TILE_STRIDE as usize).collect();
        list.push(len - TILE);
        list
    };
    let (w, h) = (width.min(TILE), height.min(TILE));
    let mut list = Vec::new();
    for &y in &starts(height) {
        for &x in &starts(width) {
            list.push((x, y, w, h));
        }
    }
    list
}

fn crop(src: &Grey, x: u32, y: u32, width: u32, height: u32) -> Grey {
    let mut data = Vec::with_capacity((width * height) as usize);
    for row in y..y + height {
        let start = (row * src.width + x) as usize;
        data.extend_from_slice(&src.data[start..start + width as usize]);
    }
    Grey { width, height, data: Zeroizing::new(data) }
}

fn scan(image: &Grey, filter: Filter, threshold: u8) -> Vec<String> {
    let (w, h) = (image.width as usize, image.height as usize);
    // 先二值化（1 是黑色，也就是 QR Code 的模組）
    let mut bits: Zeroizing<Vec<u8>> = Zeroizing::new(match filter {
        Filter::Plain | Filter::Inverted => {
            let invert = matches!(filter, Filter::Inverted);
            let px = |x: usize, y: usize| {
                let value = image.data[y * w + x];
                if invert { 255 - value } else { value }
            };
            // rqrr 自己的局部門檻
            let prepared = rqrr::PreparedImage::prepare_from_greyscale(w, h, px);
            (0..h).flat_map(|y| (0..w).map(move |x| (y, x))).map(|(y, x)| (prepared.get_pixel_at(x, y) == 1u8) as u8).collect()
        }
        Filter::Binarized => image.data.iter().map(|&v| (v <= threshold) as u8).collect(),
        Filter::BinarizedInverted => image.data.iter().map(|&v| (v > threshold) as u8).collect(),
    });
    mask_noise(&mut bits, w, h);
    let mut prepared = rqrr::PreparedImage::prepare_from_bitmap(w, h, |x, y| bits[y * w + x] == 1);
    let mut found: Vec<String> = Vec::new();
    for grid in prepared.detect_grids() {
        if let Ok((_, content)) = grid.decode() {
            if !content.is_empty() && !found.contains(&content) {
                found.push(content);
            }
        }
    }
    found
}

/// 把黑白交錯得像雜訊的區塊塗白。照片的材質、雜訊會讓 rqrr 找到大量假的定位點，
/// 每一組都要複製整張圖比對，可能跑好幾十秒；QR Code 每個模組至少 2 px 時，區塊裡黑白交錯的比例不會超過 0.25
fn mask_noise(bits: &mut [u8], w: usize, h: usize) {
    for ty in (0..h).step_by(NOISE_TILE) {
        for tx in (0..w).step_by(NOISE_TILE) {
            let (x1, y1) = ((tx + NOISE_TILE).min(w), (ty + NOISE_TILE).min(h));
            let (mut changes, mut pairs) = (0usize, 0usize);
            for y in ty..y1 {
                for x in tx..x1 {
                    let here = bits[y * w + x];
                    if x + 1 < x1 {
                        changes += (here != bits[y * w + x + 1]) as usize;
                        pairs += 1;
                    }
                    if y + 1 < y1 {
                        changes += (here != bits[(y + 1) * w + x]) as usize;
                        pairs += 1;
                    }
                }
            }
            if pairs > 0 && changes as f64 > pairs as f64 * MAX_TRANSITION_DENSITY {
                for y in ty..y1 {
                    bits[y * w + tx..y * w + x1].fill(0);
                }
            }
        }
    }
}

/// Otsu 門檻：讓「暗」與「亮」兩群的組間變異最大
fn otsu_threshold(data: &[u8]) -> u8 {
    let mut histogram = [0u64; 256];
    for &value in data {
        histogram[value as usize] += 1;
    }
    let total = data.len() as f64;
    let sum_all: f64 = histogram.iter().enumerate().map(|(i, &n)| i as f64 * n as f64).sum();
    let (mut weight_dark, mut sum_dark) = (0f64, 0f64);
    let (mut best, mut best_variance) = (127u8, -1f64);
    for (i, &n) in histogram.iter().enumerate() {
        weight_dark += n as f64;
        if weight_dark == 0.0 {
            continue;
        }
        let weight_light = total - weight_dark;
        if weight_light == 0.0 {
            break;
        }
        sum_dark += i as f64 * n as f64;
        let mean_dark = sum_dark / weight_dark;
        let mean_light = (sum_all - sum_dark) / weight_light;
        let variance = weight_dark * weight_light * (mean_dark - mean_light).powi(2);
        if variance > best_variance {
            best_variance = variance;
            best = i as u8;
        }
    }
    best
}

#[cfg(test)]
mod tests {
    use super::*;
    use image::{GrayImage, ImageFormat, Rgba, RgbaImage};
    use qrcode::{Color, QrCode};

    const URI_A: &str = "otpauth://totp/Securibit:alice@example.com?secret=JBSWY3DPEHPK3PXP&issuer=Securibit";
    const URI_B: &str = "otpauth://totp/GitHub:bob?secret=KRSXG5CTMVRXEZLUKN2XAZLSKNSWG4TFOQ&issuer=GitHub";
    const URI_C: &str = "otpauth://totp/Example:carol?secret=GEZDGNBVGY3TQOJQ&issuer=Example&digits=8";

    /// QR Code 的模組矩陣（true 是深色）
    fn modules(text: &str) -> (u32, Vec<bool>) {
        let code = QrCode::new(text.as_bytes()).unwrap();
        let width = code.width() as u32;
        (width, code.to_colors().into_iter().map(|c| c == Color::Dark).collect())
    }

    /// 在畫布上畫一個 QR Code（左上角含 4 個模組的留白）
    fn draw(canvas: &mut GrayImage, text: &str, x0: u32, y0: u32, module: u32, dark: u8, light: u8) {
        let (width, cells) = modules(text);
        let size = (width + 8) * module;
        for y in 0..size {
            for x in 0..size {
                let (mx, my) = ((x / module) as i64 - 4, (y / module) as i64 - 4);
                let inside = mx >= 0 && my >= 0 && mx < width as i64 && my < width as i64;
                let is_dark = inside && cells[(my as u32 * width + mx as u32) as usize];
                canvas.put_pixel(x0 + x, y0 + y, Luma([if is_dark { dark } else { light }]));
            }
        }
    }

    fn qr_image(text: &str, module: u32) -> GrayImage {
        let (width, _) = modules(text);
        let size = (width + 8) * module;
        let mut canvas = GrayImage::from_pixel(size, size, Luma([255]));
        draw(&mut canvas, text, 0, 0, module, 0, 255);
        canvas
    }

    fn encode(image: &DynamicImage, format: ImageFormat) -> Vec<u8> {
        let mut out = std::io::Cursor::new(Vec::new());
        image.write_to(&mut out, format).unwrap();
        out.into_inner()
    }

    fn png(image: GrayImage) -> Vec<u8> {
        encode(&DynamicImage::ImageLuma8(image), ImageFormat::Png)
    }

    fn jpeg(image: GrayImage) -> Vec<u8> {
        // JPEG 編碼器要 RGB，順便模擬一般的彩色截圖
        encode(&DynamicImage::ImageRgb8(DynamicImage::ImageLuma8(image).to_rgb8()), ImageFormat::Jpeg)
    }

    #[test]
    fn reads_a_png_screenshot() {
        assert_eq!(decode_qr_image(&png(qr_image(URI_A, 8))).unwrap(), vec![URI_A]);
    }

    #[test]
    fn reads_a_jpeg_screenshot() {
        assert_eq!(decode_qr_image(&jpeg(qr_image(URI_B, 6))).unwrap(), vec![URI_B]);
    }

    #[test]
    fn reads_other_formats() {
        let image = DynamicImage::ImageLuma8(qr_image(URI_C, 6));
        for format in [ImageFormat::Bmp, ImageFormat::Gif, ImageFormat::WebP] {
            let image = DynamicImage::ImageRgba8(image.to_rgba8());
            assert_eq!(decode_qr_image(&encode(&image, format)).unwrap(), vec![URI_C], "{format:?}");
        }
    }

    #[test]
    fn reads_every_code_in_one_image() {
        let mut canvas = GrayImage::from_pixel(1400, 600, Luma([240]));
        draw(&mut canvas, URI_A, 40, 60, 6, 20, 255);
        draw(&mut canvas, URI_B, 500, 40, 5, 20, 255);
        draw(&mut canvas, URI_C, 1000, 120, 7, 20, 255);
        let mut found = decode_qr_image(&png(canvas)).unwrap();
        found.sort();
        let mut expected = vec![URI_A, URI_B, URI_C];
        expected.sort();
        assert_eq!(found, expected);
    }

    #[test]
    fn same_code_twice_is_returned_once() {
        let mut canvas = GrayImage::from_pixel(900, 450, Luma([255]));
        draw(&mut canvas, URI_A, 20, 20, 7, 0, 255);
        draw(&mut canvas, URI_A, 460, 20, 7, 0, 255);
        assert_eq!(decode_qr_image(&png(canvas)).unwrap(), vec![URI_A]);
    }

    #[test]
    fn reads_inverted_dark_mode_codes() {
        // 深色模式：淺色模組、深色背景
        let mut canvas = GrayImage::from_pixel(700, 900, Luma([28]));
        draw(&mut canvas, URI_A, 120, 200, 7, 242, 28);
        assert_eq!(decode_qr_image(&png(canvas.clone())).unwrap(), vec![URI_A]);
        assert_eq!(decode_qr_image(&jpeg(canvas)).unwrap(), vec![URI_A]);
    }

    #[test]
    fn fallbacks_are_needed() {
        // 反色與小圖只靠第一次（原尺寸、rqrr 自己的門檻）讀不到，要靠後面的嘗試
        let mut dark = GrayImage::from_pixel(700, 900, Luma([28]));
        draw(&mut dark, URI_A, 120, 200, 7, 242, 28);
        let big = qr_image(URI_C, 8);
        let side = big.width() * 3 / 16;
        let small = imageops::resize(&big, side, side, FilterType::Triangle);
        for image in [dark, small] {
            let grey = decode_grey(&png(image)).unwrap();
            assert!(scan(&grey, Filter::Plain, otsu_threshold(&grey.data)).is_empty());
            assert!(!scan_all(&grey, Instant::now() + TIME_BUDGET).is_empty());
        }
    }

    #[test]
    fn worst_case_is_bounded() {
        // 很大、沒有 QR Code 的雜訊圖：每種嘗試都會跑完，但不能卡太久
        let mut seed = 0x2545_f491_u32;
        let canvas = GrayImage::from_fn(4032, 3024, |_, _| {
            seed ^= seed << 13;
            seed ^= seed >> 17;
            seed ^= seed << 5;
            Luma([(seed >> 24) as u8])
        });
        for texture in [canvas.clone(), imageops::blur(&canvas, 0.8)] {
            let bytes = png(texture);
            let started = Instant::now();
            let result = decode_qr_image(&bytes);
            assert!(matches!(result.as_deref(), Ok([]) | Err(QrImageError::Timeout)), "{result:?}");
            // 解碼 PNG 不算在上限內；debug 版慢很多，只在 release 檢查時間
            if !cfg!(debug_assertions) {
                assert!(started.elapsed() < HARD_LIMIT + Duration::from_secs(2));
            }
        }
    }

    #[test]
    fn reads_low_contrast_codes() {
        let mut canvas = GrayImage::from_pixel(600, 600, Luma([150]));
        draw(&mut canvas, URI_B, 100, 100, 6, 105, 150);
        assert_eq!(decode_qr_image(&jpeg(canvas)).unwrap(), vec![URI_B]);
    }

    #[test]
    fn reads_small_images() {
        // 先畫清楚的，再縮小成每個模組不到 2 px（像被縮圖過的截圖）
        let big = qr_image(URI_C, 8);
        let side = big.width() * 3 / 16;
        let small = imageops::resize(&big, side, side, FilterType::Triangle);
        assert!(small.width() < 90);
        assert_eq!(decode_qr_image(&png(small)).unwrap(), vec![URI_C]);
    }

    #[test]
    fn reads_large_photos() {
        // 大圖會先縮小再辨識
        let mut canvas = GrayImage::from_pixel(4032, 3024, Luma([200]));
        draw(&mut canvas, URI_A, 1500, 900, 18, 30, 235);
        let started = Instant::now();
        assert_eq!(decode_qr_image(&jpeg(canvas)).unwrap(), vec![URI_A]);
        if !cfg!(debug_assertions) {
            assert!(started.elapsed() < Duration::from_secs(3));
        }
    }

    #[test]
    fn transparent_background_counts_as_white() {
        let gray = qr_image(URI_B, 6);
        let mut rgba = RgbaImage::new(gray.width(), gray.height());
        for (x, y, px) in gray.enumerate_pixels() {
            // 深色模組不透明，其他全透明（透明像素的顏色是黑色，沒處理的話整張都是黑的）
            let alpha = if px.0[0] < 128 { 255 } else { 0 };
            rgba.put_pixel(x, y, Rgba([0, 0, 0, alpha]));
        }
        let bytes = encode(&DynamicImage::ImageRgba8(rgba), ImageFormat::Png);
        assert_eq!(decode_qr_image(&bytes).unwrap(), vec![URI_B]);
    }

    #[test]
    fn reads_google_authenticator_exports() {
        // 匯出的 otpauth-migration:// 很長（版本高、模組小）
        let data: String = (0..560).map(|i| ['A', 'b', '3', '%', '2', 'F', 'z', 'Q'][i % 8]).collect();
        let text = format!("otpauth-migration://offline?data={data}");
        let mut canvas = GrayImage::from_pixel(1170, 2532, Luma([250]));
        draw(&mut canvas, &text, 150, 700, 6, 0, 255);
        assert_eq!(decode_qr_image(&png(canvas)).unwrap(), vec![text]);
    }

    #[test]
    fn keeps_unicode_text() {
        let text = "otpauth://totp/%E5%B9%A3%E5%8F%8B:測試帳號?secret=JBSWY3DPEHPK3PXP&issuer=幣友";
        assert_eq!(decode_qr_image(&png(qr_image(text, 6))).unwrap(), vec![text]);
    }

    #[test]
    fn image_without_code_is_empty() {
        let mut canvas = GrayImage::from_pixel(800, 600, Luma([255]));
        for y in 0..600 {
            for x in 0..800 {
                canvas.put_pixel(x, y, Luma([((x * 7 + y * 13) % 256) as u8]));
            }
        }
        assert!(decode_qr_image(&png(canvas.clone())).unwrap().is_empty());
        assert!(decode_qr_image(&jpeg(canvas)).unwrap().is_empty());
        assert!(decode_qr_image(&png(GrayImage::from_pixel(1, 1, Luma([0])))).unwrap().is_empty());
    }

    #[test]
    fn broken_files_are_errors() {
        assert_eq!(decode_qr_image(&[]), Err(QrImageError::Empty));
        assert_eq!(decode_qr_image(b"otpauth://totp/x?secret=ABC"), Err(QrImageError::UnsupportedFormat));

        // PNG 截斷到一半
        let bytes = png(qr_image(URI_A, 8));
        assert_eq!(decode_qr_image(&bytes[..bytes.len() / 2]), Err(QrImageError::Corrupt));
        // 只有 PNG 的檔頭
        let mut garbage = b"\x89PNG\r\n\x1a\n".to_vec();
        garbage.extend(std::iter::repeat_n(0xA5, 500));
        assert_eq!(decode_qr_image(&garbage), Err(QrImageError::Corrupt));
        // JPEG 只有開頭
        let bytes = jpeg(qr_image(URI_A, 8));
        assert_eq!(decode_qr_image(&bytes[..64]), Err(QrImageError::Corrupt));
    }

    #[test]
    fn heic_and_avif_are_rejected_clearly() {
        let mut heic = vec![0, 0, 0, 0x18];
        heic.extend_from_slice(b"ftypheic\0\0\0\0mif1heic");
        assert_eq!(decode_qr_image(&heic), Err(QrImageError::Heic));
        assert!(QrImageError::Heic.to_string().contains("PNG 或 JPG"));

        let mut avif = vec![0, 0, 0, 0x1c];
        avif.extend_from_slice(b"ftypavif\0\0\0\0avifmif1miaf");
        assert_eq!(decode_qr_image(&avif), Err(QrImageError::UnsupportedFormat));
    }

    #[test]
    fn tiff_is_not_compiled_in() {
        let bytes = b"II*\0\x08\0\0\0\0\0\0\0\0\0\0\0".to_vec();
        assert_eq!(decode_qr_image(&bytes), Err(QrImageError::UnsupportedFormat));
    }

    #[test]
    fn oversized_files_are_rejected_before_decoding() {
        let mut bytes = png(qr_image(URI_A, 4));
        bytes.resize(MAX_FILE_BYTES + 1, 0);
        assert_eq!(decode_qr_image(&bytes), Err(QrImageError::TooLarge));
    }

    #[test]
    fn huge_dimensions_are_rejected() {
        // 很小的 PNG，但宣稱 20000 × 20000
        let image = GrayImage::from_pixel(20_000, 1, Luma([255]));
        assert_eq!(decode_qr_image(&png(image)), Err(QrImageError::TooManyPixels));
    }

    #[test]
    fn passes_are_bounded() {
        let whole = |long_side| Pass { long_side, tiled: false };
        assert_eq!(passes(1200), vec![whole(1200), whole(600)]);
        assert_eq!(passes(4032), vec![whole(1800), whole(1000), Pass { long_side: 3000, tiled: true }]);
        assert_eq!(passes(2000), vec![whole(1800), whole(1000), Pass { long_side: 2000, tiled: true }]);
        assert_eq!(passes(80), vec![whole(80), whole(640)]);
        assert_eq!(passes(1), vec![whole(1), whole(8)]);
    }

    #[test]
    fn tiles_cover_the_image() {
        assert_eq!(tiles(800, 600), vec![(0, 0, 800, 600)]);
        let list = tiles(3000, 2250);
        assert_eq!(list.len(), 4 * 3);
        assert!(list.contains(&(1800, 1050, 1200, 1200)));
        // 每一塊都在圖裡面，而且相鄰的區塊至少重疊 400 px
        for &(x, y, w, h) in &list {
            assert!(x + w <= 3000 && y + h <= 2250);
        }
        let xs: Vec<u32> = list.iter().filter(|t| t.1 == 0).map(|t| t.0).collect();
        assert_eq!(xs, vec![0, 800, 1600, 1800]);
    }

    #[test]
    fn tiny_code_in_a_large_photo() {
        // 4000 px 的照片裡只有 150 px 的 QR Code：縮成 1800、1000 都太小，要靠切塊
        let mut canvas = GrayImage::from_pixel(4000, 3000, Luma([190]));
        draw(&mut canvas, URI_B, 2900, 2100, 3, 25, 230);
        let grey = decode_grey(&png(canvas)).unwrap();
        let small = resized(&grey, BASE_LONG_SIDE);
        assert!(scan(&small, Filter::Plain, otsu_threshold(&small.data)).is_empty());
        // 這裡測切塊，不測時間（debug 版慢很多，5 秒內跑不到右下角的區塊）
        assert_eq!(scan_all(&grey, Instant::now() + Duration::from_secs(120)), vec![URI_B]);
    }

    #[test]
    fn code_on_a_noisy_background() {
        // 拍照時 QR Code 旁邊是有材質的桌面
        let mut seed = 0x9e37_79b9_u32;
        let mut canvas = GrayImage::from_fn(1600, 1200, |_, _| {
            seed ^= seed << 13;
            seed ^= seed >> 17;
            seed ^= seed << 5;
            Luma([(seed >> 24) as u8])
        });
        draw(&mut canvas, URI_C, 500, 300, 8, 10, 250);
        assert_eq!(decode_qr_image(&png(canvas)).unwrap(), vec![URI_C]);
    }

    #[test]
    fn gives_up_after_the_hard_limit() {
        // 很大的雜訊圖、幾乎不給時間：回報逾時而不是一直等
        let mut seed = 0x2545_f491_u32;
        let canvas = GrayImage::from_fn(3000, 2250, |_, _| {
            seed ^= seed << 13;
            seed ^= seed >> 17;
            seed ^= seed << 5;
            Luma([(seed >> 24) as u8])
        });
        let bytes = png(imageops::blur(&canvas, 0.8));
        let started = Instant::now();
        assert_eq!(decode_within(&bytes, Duration::ZERO, Duration::from_millis(1)), Err(QrImageError::Timeout));
        assert!(started.elapsed() < Duration::from_secs(5));
    }

    #[test]
    fn otsu_splits_two_levels() {
        let data: Vec<u8> = [vec![40u8; 100], vec![200u8; 100]].concat();
        let t = otsu_threshold(&data);
        assert!((40..200).contains(&t));
    }
}

