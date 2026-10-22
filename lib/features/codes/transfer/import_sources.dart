import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../core/platform.dart';
import '../../../src/rust/api/qr.dart' as core;

/*
 * 從檔案匯入（同網站 QrImport 的「上傳圖片或備份檔」）：
 * 文字備份檔直接讀；圖片在 iOS、Android、macOS 用 mobile_scanner 的 analyzeImage（系統內建的辨識，比較準），
 * Linux、Windows 沒有 mobile_scanner，改用 Rust 核心（rust/core/src/qr_image.rs，支援 PNG、JPG、WebP、GIF、BMP）。
 */

/// 選檔的種類：手機分成相簿圖片與備份檔（iOS 的相簿和檔案是不同的選擇器），桌面合在一起
enum ImportFileKind { image, backup, any }

const _imageExtensions = ['png', 'jpg', 'jpeg', 'gif', 'webp', 'heic', 'heif', 'bmp', 'tif', 'tiff'];
// Rust 版（Linux、Windows）不支援 TIFF；HEIC 仍然列出來，選到時說明要改用 PNG 或 JPG
const _rustImageExtensions = ['png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp', 'heic', 'heif'];
const _heicExtensions = ['heic', 'heif'];
const _textExtensions = ['txt'];

// 備份檔不會大到這樣，太大的多半選錯檔案
const _maxTextBytes = 2 * 1024 * 1024;
// 圖片的大小上限（同 Rust 的 qr_image::MAX_FILE_BYTES），先在這裡擋下，不用把整個檔案讀進記憶體
const _maxImageBytes = 20 * 1024 * 1024;

const _notFound = PickedImport.error('找不到 QR Code', '圖片中找不到 QR Code，請換一張清楚一點的截圖。');
const _notImage = PickedImport.error('無法讀取圖片', '這個檔案無法當成圖片讀取，請改用 PNG 或 JPG 截圖。');

/// 選檔的結果：text 是 QR Code 或檔案的內容；失敗時有 errorTitle 與 errorMessage
class PickedImport {
  const PickedImport.text(String this.text)
      : errorTitle = null,
        errorMessage = null;

  const PickedImport.error(String this.errorTitle, String this.errorMessage) : text = null;

  final String? text;
  final String? errorTitle;
  final String? errorMessage;
}

bool isTextFileName(String name) => _textExtensions.any((ext) => name.toLowerCase().endsWith('.$ext'));

/// 選到的一個檔案與讀出來的內容
typedef PickedFile = ({String name, PickedImport result});

/// 開檔案選擇器（可以一次選多個）並逐一讀出內容；使用者取消時回傳 null。
/// 選擇視窗開不起來時回傳一筆沒有檔名的錯誤
Future<List<PickedFile>?> pickImportFiles(ImportFileKind kind) async {
  final canImage = AppPlatform.canReadQrImage;
  final FilePickerResult? result;
  try {
    result = switch (kind) {
      ImportFileKind.image => await FilePicker.pickFiles(type: FileType.image, allowMultiple: true),
      ImportFileKind.backup => await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: _textExtensions, allowMultiple: true),
      ImportFileKind.any => await FilePicker.pickFiles(
          type: FileType.custom,
          allowedExtensions: [
            if (canImage) ...(AppPlatform.usesRustQrImage ? _rustImageExtensions : _imageExtensions),
            ..._textExtensions,
          ],
          allowMultiple: true,
        ),
    };
  } catch (error) {
    return [(name: '', result: PickedImport.error('無法開啟檔案', '無法開啟選擇檔案的視窗：$error'))];
  }
  final files = result?.files ?? const <PlatformFile>[];
  if (files.isEmpty) return null;

  final picked = <PickedFile>[];
  for (final file in files) {
    final path = file.path;
    final PickedImport read;
    if (path == null) {
      read = const PickedImport.error('無法讀取檔案', '讀不到這個檔案，請換一個位置再試一次。');
    } else if (kind == ImportFileKind.backup || isTextFileName(file.name) || !canImage) {
      // 文字備份檔
      read = await readBackupFile(path);
    } else {
      read = await decodeQrImage(path);
    }
    picked.add((name: file.name, result: read));
  }
  return picked;
}

/// 讀文字備份檔
Future<PickedImport> readBackupFile(String path) async {
  try {
    final file = File(path);
    if (await file.length() > _maxTextBytes) {
      return const PickedImport.error('無法匯入', '檔案太大，不像是驗證碼的備份檔。');
    }
    return PickedImport.text(utf8.decode(await file.readAsBytes(), allowMalformed: true));
  } catch (_) {
    return const PickedImport.error('無法讀取檔案', '這個檔案無法當成文字讀取，請選擇匯出的 .txt 備份檔。');
  }
}

/// 從圖片找 QR Code（一張圖有好幾個 QR Code 時全部讀出來，一行一個）
Future<PickedImport> decodeQrImage(String path) async {
  if (AppPlatform.usesRustQrImage) return decodeQrImageWithRust(path);
  final controller = MobileScannerController(autoStart: false, formats: const [BarcodeFormat.qrCode]);
  try {
    final capture = await controller.analyzeImage(path, formats: const [BarcodeFormat.qrCode]);
    final values = {...?capture?.barcodes.map((b) => b.rawValue).whereType<String>().where((v) => v.isNotEmpty)};
    if (values.isEmpty) return _notFound;
    return PickedImport.text(values.join('\n'));
  } catch (_) {
    return _notImage;
  } finally {
    await controller.dispose();
  }
}

/// Linux、Windows：用 Rust 核心辨識（不是 sync 的函式，在 Rust 的執行緒池跑，不會卡住畫面）
@visibleForTesting
Future<PickedImport> decodeQrImageWithRust(String path) async {
  final lower = path.toLowerCase();
  if (_heicExtensions.any((ext) => lower.endsWith('.$ext'))) {
    return const PickedImport.error('無法讀取圖片', '不支援 HEIC／HEIF 圖片（iPhone 照片的格式），請先轉成 PNG 或 JPG 再試一次。');
  }
  final Uint8List bytes;
  try {
    final file = File(path);
    if (await file.length() > _maxImageBytes) {
      return const PickedImport.error('無法讀取圖片', '圖片超過 20 MB，請改用較小的截圖。');
    }
    bytes = await file.readAsBytes();
  } catch (_) {
    return const PickedImport.error('無法讀取檔案', '讀不到這個檔案，請換一個位置再試一次。');
  }
  try {
    final values = await core.decodeQrImage(bytes: bytes);
    if (values.isEmpty) return _notFound;
    return PickedImport.text(values.join('\n'));
  } on String catch (message) {
    // Rust 回傳的錯誤訊息（檔案太大、HEIC、格式不支援、壞掉的檔案、辨識太久）
    return PickedImport.error('無法讀取圖片', message);
  } catch (_) {
    return _notImage;
  } finally {
    // 圖片內容等同金鑰，用完歸零（Rust 那邊的複本也會歸零）
    bytes.fillRange(0, bytes.length, 0);
  }
}
