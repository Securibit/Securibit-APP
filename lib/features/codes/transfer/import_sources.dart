import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../core/platform.dart';

/*
 * 從檔案匯入（同網站 QrImport 的「上傳圖片或備份檔」）：
 * 文字備份檔直接讀；圖片用 mobile_scanner 的 analyzeImage 找 QR Code（iOS、Android、macOS，Linux 不支援）。
 */

/// 選檔的種類：手機分成相簿圖片與備份檔（iOS 的相簿和檔案是不同的選擇器），桌面合在一起
enum ImportFileKind { image, backup, any }

const _imageExtensions = ['png', 'jpg', 'jpeg', 'gif', 'webp', 'heic', 'heif', 'bmp', 'tif', 'tiff'];
const _textExtensions = ['txt'];

// 備份檔不會大到這樣，太大的多半選錯檔案
const _maxTextBytes = 2 * 1024 * 1024;

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

/// 開檔案選擇器並讀出內容；使用者取消時回傳 null
Future<PickedImport?> pickImportFile(ImportFileKind kind) async {
  final canImage = AppPlatform.canReadQrImage;
  final FilePickerResult? result;
  try {
    result = switch (kind) {
      ImportFileKind.image => await FilePicker.pickFiles(type: FileType.image),
      ImportFileKind.backup => await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: _textExtensions),
      ImportFileKind.any => await FilePicker.pickFiles(
          type: FileType.custom,
          allowedExtensions: [if (canImage) ..._imageExtensions, ..._textExtensions],
        ),
    };
  } catch (error) {
    return PickedImport.error('無法開啟檔案', '無法開啟選擇檔案的視窗：$error');
  }
  final file = result?.files.firstOrNull;
  if (file == null) return null;
  final path = file.path;
  if (path == null) return const PickedImport.error('無法讀取檔案', '讀不到這個檔案，請換一個位置再試一次。');

  // 文字備份檔
  if (kind == ImportFileKind.backup || isTextFileName(file.name) || !canImage) {
    return readBackupFile(path);
  }
  return decodeQrImage(path);
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

/// 從圖片找 QR Code
Future<PickedImport> decodeQrImage(String path) async {
  final controller = MobileScannerController(autoStart: false, formats: const [BarcodeFormat.qrCode]);
  try {
    final capture = await controller.analyzeImage(path, formats: const [BarcodeFormat.qrCode]);
    final value = capture?.barcodes.map((b) => b.rawValue).whereType<String>().where((v) => v.isNotEmpty).firstOrNull;
    if (value == null) return const PickedImport.error('找不到 QR Code', '圖片中找不到 QR Code，請換一張清楚一點的截圖。');
    return PickedImport.text(value);
  } catch (_) {
    return const PickedImport.error('無法讀取圖片', '這個檔案無法當成圖片讀取，請改用 PNG 或 JPG 截圖。');
  } finally {
    await controller.dispose();
  }
}
