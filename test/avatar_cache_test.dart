import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:securibit/core/widgets/avatar_cache.dart';

// 頭像暫存：下載成功記住、沒有網路時沿用、不是圖片的回應不收（測試環境沒有暫存資料夾，只測記憶體這一層）
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final png = Uint8List.fromList([137, 80, 78, 71, 1, 2, 3]);

  setUp(AvatarCache.clear);

  test('下載成功後記住，離線時沿用', () async {
    var calls = 0;
    AvatarCache.fetch = (uri) async {
      calls++;
      return http.Response.bytes(png, 200, headers: {'content-type': 'image/png'});
    };
    expect(await AvatarCache.load('https://example.com/a.png'), png);
    expect(AvatarCache.peek('https://example.com/a.png'), png);

    AvatarCache.fetch = (uri) async => throw Exception('offline');
    expect(await AvatarCache.load('https://example.com/a.png'), png);
    expect(calls, 1);
  });

  test('不是圖片、或不是 http(s) 的網址都不收', () async {
    AvatarCache.fetch = (uri) async => http.Response('<html>', 200, headers: {'content-type': 'text/html'});
    expect(await AvatarCache.load('https://example.com/b.png'), isNull);
    expect(await AvatarCache.load('file:///etc/passwd'), isNull);
    expect(AvatarCache.peek('https://example.com/b.png'), isNull);
  });

  test('登出清掉', () async {
    AvatarCache.fetch = (uri) async => http.Response.bytes(png, 200, headers: {'content-type': 'image/png'});
    await AvatarCache.load('https://example.com/c.png');
    await AvatarCache.clear();
    expect(AvatarCache.peek('https://example.com/c.png'), isNull);
  });
}
