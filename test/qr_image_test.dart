import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:securibit/features/codes/transfer/import_sources.dart';
import 'package:securibit/src/rust/api/qr.dart' as core;

// Linux 從圖片讀 QR Code 用的 Rust 版（rust/core/src/qr_image.rs）：經過 flutter_rust_bridge 的結果與錯誤訊息。
// 各種圖片（反色、小圖、大圖、雜訊）的辨識在 Rust 的單元測試

const _uriA = 'otpauth://totp/Securibit:alice@example.com?secret=JBSWY3DPEHPK3PXP&issuer=Securibit';
const _uriB = 'otpauth://totp/GitHub:bob?secret=KRSXG5CTMVRXEZLUKN2XAZLSKNSWG4TFOQ&issuer=GitHub';

void main() {
  late Directory temp;

  setUp(() => temp = Directory.systemTemp.createTempSync('securibit-qr-'));
  tearDown(() => temp.deleteSync(recursive: true));

  String copyAs(String fixture, String name) => File('test/fixtures/$fixture').copySync('${temp.path}/$name').path;

  String write(String name, List<int> bytes) {
    final file = File('${temp.path}/$name')..writeAsBytesSync(bytes);
    return file.path;
  }

  test('讀出圖片裡的 QR Code', () async {
    expect(await core.decodeQrImage(bytes: File('test/fixtures/qr_single.png').readAsBytesSync()), [_uriA]);
    final picked = await decodeQrImageWithRust(copyAs('qr_single.png', 'shot.png'));
    expect(picked.text, _uriA);
    expect(picked.errorTitle, isNull);
  });

  test('一張圖有好幾個 QR Code 時一行一個', () async {
    final picked = await decodeQrImageWithRust(copyAs('qr_two.png', 'two.png'));
    expect(picked.text?.split('\n')?..sort(), [_uriA, _uriB]..sort());
  });

  test('沒有 QR Code 的圖片', () async {
    // 1×1 的白色 PNG
    final png = Uint8List.fromList([
      0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00, 0x00, 0x0d, 0x49, 0x48, 0x44, 0x52, //
      0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x00, 0x00, 0x00, 0x00, 0x3a, 0x7e, 0x9b,
      0x55, 0x00, 0x00, 0x00, 0x0a, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9c, 0x63, 0xf8, 0x0f, 0x00, 0x01,
      0x01, 0x01, 0x00, 0xb1, 0x38, 0xf6, 0x14, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4e, 0x44, 0xae,
      0x42, 0x60, 0x82,
    ]);
    expect(await core.decodeQrImage(bytes: png), isEmpty);
    final picked = await decodeQrImageWithRust(write('blank.png', png));
    expect(picked.errorTitle, '找不到 QR Code');
  });

  test('壞掉的檔案與不支援的格式給中文訊息', () async {
    await expectLater(core.decodeQrImage(bytes: Uint8List(0)), throwsA(contains('檔案是空的')));

    final broken = await decodeQrImageWithRust(write('broken.png', [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 1, 2, 3]));
    expect(broken.errorTitle, '無法讀取圖片');
    expect(broken.errorMessage, contains('已損壞'));

    final text = await decodeQrImageWithRust(write('notes.png', 'otpauth://totp/x?secret=ABC'.codeUnits));
    expect(text.errorMessage, contains('不支援這種圖片格式'));
  });

  test('HEIC 請使用者改用 PNG 或 JPG', () async {
    // 副檔名是 .heic：不讀檔就回覆
    final byName = await decodeQrImageWithRust(write('IMG_0001.HEIC', [0]));
    expect(byName.errorMessage, allOf(contains('HEIC'), contains('PNG 或 JPG')));
    // 副檔名改過，但內容是 HEIC：Rust 看檔頭判斷
    final heic = [0, 0, 0, 0x18, ...'ftypheic'.codeUnits, 0, 0, 0, 0, ...'mif1heic'.codeUnits];
    final byContent = await decodeQrImageWithRust(write('photo.jpg', heic));
    expect(byContent.errorMessage, allOf(contains('HEIC'), contains('PNG 或 JPG')));
  });

  test('超過 20 MB 的圖片不讀', () async {
    final path = write('huge.png', []);
    final file = File(path).openSync(mode: FileMode.write)..truncateSync(20 * 1024 * 1024 + 1);
    file.closeSync();
    final picked = await decodeQrImageWithRust(path);
    expect(picked.errorMessage, contains('20 MB'));
  });
}
