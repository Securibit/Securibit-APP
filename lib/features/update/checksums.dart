import 'dart:io';

import 'package:crypto/crypto.dart';

/*
 * 下載的安裝檔要和 Release 附的 SHA256SUMS.txt 一致才安裝（release.py、make checksums 產生）。
 * 格式和 sha256sum／shasum -a 256 的輸出相同：一行一個「<64 位十六進位>  <檔名>」，檔名前的 * 是二進位模式，空行與 # 開頭的註解略過。
 */
Map<String, String> parseChecksums(String text) {
  final sums = <String, String>{};
  for (final raw in text.split('\n')) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    final match = RegExp(r'^([0-9a-fA-F]{64})\s+\*?(.+)$').firstMatch(line);
    if (match == null) continue;
    sums[match[2]!.trim()] = match[1]!.toLowerCase();
  }
  return sums;
}

/// 清單裡這個檔名的檢查碼（先找完全相同的，再不分大小寫）；沒有就是 null
String? checksumFor(Map<String, String> sums, String name) {
  final exact = sums[name];
  if (exact != null) return exact;
  for (final entry in sums.entries) {
    if (entry.key.toLowerCase() == name.toLowerCase()) return entry.value;
  }
  return null;
}

/// 檔案的 SHA-256（小寫十六進位），邊讀邊算，不會整個讀進記憶體
Future<String> sha256OfFile(File file) async => (await sha256.bind(file.openRead()).first).toString();
