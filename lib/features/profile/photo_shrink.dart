import 'dart:typed_data';
import 'dart:ui' as ui;

import '../../src/rust/api/photo.dart' as core;

/*
 * 上傳前縮小圖片（同網站上傳前在瀏覽器縮小）：網站的請求大小上限約 4.5 MB，超過 4 MB 的圖片先縮小再傳。
 * Flutter 解碼並縮到最長邊 2048（不夠小再縮），Rust 編成 JPEG；伺服器之後會再轉成 WebP。
 */

/// 不用縮小就能直接上傳的大小
const uploadMaxBytes = 4 * 1024 * 1024;

// 依序嘗試：最長邊、JPEG 品質
const _steps = [(2048, 85), (1600, 80), (1280, 75)];

/// 縮好的圖片與檔名
typedef ShrunkPhoto = ({Uint8List bytes, String filename});

// 伺服器（sharp）讀不了 HEIC，iPhone 的照片一律先轉成 JPEG
final _alwaysConvert = RegExp(r'\.(heic|heif)$', caseSensitive: false);

/// 小於 4 MB 原樣回傳（HEIC 一律轉成 JPEG）；太大時縮小成 JPEG。縮了還是太大、或讀不出來時回傳 null
Future<ShrunkPhoto?> shrinkForUpload(Uint8List bytes, String filename) async {
  if (bytes.length <= uploadMaxBytes && !_alwaysConvert.hasMatch(filename)) return (bytes: bytes, filename: filename);
  final dot = filename.lastIndexOf('.');
  final jpegName = '${dot > 0 ? filename.substring(0, dot) : filename}.jpg';
  for (final (side, quality) in _steps) {
    final jpeg = await _resizeJpeg(bytes, side, quality);
    if (jpeg == null) return null;
    if (jpeg.length <= uploadMaxBytes) return (bytes: jpeg, filename: jpegName);
  }
  return null;
}

Future<Uint8List?> _resizeJpeg(Uint8List bytes, int maxSide, int quality) async {
  ui.ImmutableBuffer? buffer;
  ui.ImageDescriptor? descriptor;
  ui.Codec? codec;
  ui.Image? image;
  try {
    buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    final (width, height) = fitWithin(descriptor.width, descriptor.height, maxSide);
    codec = await descriptor.instantiateCodec(targetWidth: width, targetHeight: height);
    image = (await codec.getNextFrame()).image;
    // 不預乘透明度的 RGBA，Rust 把透明的地方疊在白色上
    final rgba = await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
    if (rgba == null) return null;
    return await core.photoEncodeJpeg(width: image.width, height: image.height, rgba: rgba.buffer.asUint8List(), quality: quality);
  } catch (_) {
    return null;
  } finally {
    image?.dispose();
    codec?.dispose();
    descriptor?.dispose();
    buffer?.dispose();
  }
}

/// 等比例縮到最長邊不超過 maxSide（本來就比較小時不放大）
(int, int) fitWithin(int width, int height, int maxSide) {
  final longest = width > height ? width : height;
  if (longest <= maxSide || longest == 0) return (width, height);
  final scale = maxSide / longest;
  int fit(int value) => (value * scale).round().clamp(1, maxSide);
  return (fit(width), fit(height));
}
