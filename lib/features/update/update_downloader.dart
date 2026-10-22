import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// 下載失敗（網路、伺服器錯誤、檔案太大）；會安靜地重試
class UpdateDownloadException implements Exception {
  const UpdateDownloadException(this.message);

  final String message;

  @override
  String toString() => message;
}

/*
 * 下載更新檔：GitHub 的附件網址會轉址到 objects.githubusercontent.com（http 套件會跟著轉）。
 * 先寫到 <檔名>.part，下載完整才改成正式檔名，中斷時不會留下半個檔案被當成下載好的。
 * 只接受 https；開發測試用 UPDATE_FEED_URL 指到本機時才允許 http（allowInsecure）。
 */
class UpdateDownloader {
  UpdateDownloader(this._client, {required this.userAgent, this.allowInsecure = false});

  static const _idleTimeout = Duration(seconds: 30);

  final http.Client _client;
  final String userAgent;
  final bool allowInsecure;

  void _checkScheme(Uri uri) {
    if (uri.scheme == 'https' || (allowInsecure && uri.scheme == 'http')) return;
    throw UpdateDownloadException('不接受的網址：$uri');
  }

  /// 讀小的文字檔（SHA256SUMS.txt），超過 maxBytes 就當作錯誤
  Future<String> fetchText(Uri uri, {int maxBytes = 256 * 1024}) async {
    _checkScheme(uri);
    final res = await _client.get(uri, headers: {'User-Agent': userAgent}).timeout(const Duration(seconds: 30));
    if (res.statusCode != 200) throw UpdateDownloadException('HTTP ${res.statusCode}');
    if (res.bodyBytes.length > maxBytes) throw const UpdateDownloadException('檔案太大');
    return utf8.decode(res.bodyBytes, allowMalformed: true);
  }

  /// 下載到 dest；onProgress 收到已下載與總共的位元組（伺服器沒說總共多大時是 null）
  Future<void> download(Uri uri, File dest, {void Function(int received, int? total)? onProgress}) async {
    _checkScheme(uri);
    final request = http.Request('GET', uri)..headers['User-Agent'] = userAgent;
    final res = await _client.send(request).timeout(const Duration(seconds: 30));
    if (res.statusCode != 200) {
      await res.stream.drain<void>().catchError((_) {});
      throw UpdateDownloadException('HTTP ${res.statusCode}');
    }
    final total = res.contentLength;
    final part = File('${dest.path}.part');
    await part.parent.create(recursive: true);
    final sink = part.openWrite();
    var received = 0;
    try {
      await for (final chunk in res.stream.timeout(_idleTimeout)) {
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(received, total);
      }
      await sink.flush();
    } catch (e) {
      await sink.close().catchError((_) {});
      await part.delete().catchError((_) => part);
      throw UpdateDownloadException('下載中斷：$e');
    }
    await sink.close();
    if (total != null && received != total) {
      await part.delete().catchError((_) => part);
      throw UpdateDownloadException('下載不完整（$received / $total）');
    }
    if (await dest.exists()) await dest.delete();
    await part.rename(dest.path);
  }
}
