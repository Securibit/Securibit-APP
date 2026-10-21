import 'dart:typed_data';

// RFC 4648 Base32（TOTP 金鑰的標準格式），不輸出結尾的 = 補位（同網站 src/lib/totp/base32.ts）
const _alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

String base32Encode(List<int> bytes) {
  var bits = 0;
  var value = 0;
  final output = StringBuffer();
  for (final byte in bytes) {
    value = ((value << 8) | byte) & 0xFFFFFFFF;
    bits += 8;
    while (bits >= 5) {
      output.write(_alphabet[(value >> (bits - 5)) & 31]);
      bits -= 5;
    }
  }
  if (bits > 0) output.write(_alphabet[(value << (5 - bits)) & 31]);
  return output.toString();
}

/// 傳入前請先 normalizeSecret（大寫、無空白、無 =）；有不合法字元會丟 FormatException
Uint8List base32Decode(String input) {
  var bits = 0;
  var value = 0;
  final output = <int>[];
  for (final char in input.split('')) {
    final index = _alphabet.indexOf(char);
    if (index < 0) throw FormatException('不是 Base32 字元：$char');
    value = ((value << 5) | index) & 0xFFFFFFFF;
    bits += 5;
    if (bits >= 8) {
      output.add((value >> (bits - 8)) & 255);
      bits -= 8;
    }
  }
  return Uint8List.fromList(output);
}
