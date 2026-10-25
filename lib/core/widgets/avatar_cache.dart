import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/*
 * 頭像暫存：下載過的頭像存在 App 的暫存資料夾（<cache>/avatars/<網址的 SHA-256>），
 * 沒有網路時先顯示存著的那份；有網路時每次開 App 對同一張頭像只再下載一次來更新。
 * 系統清暫存、或登出（clear）時就沒了，再顯示名字的第一個字。讀寫失敗一律當作沒有暫存，不影響畫面。
 */
class AvatarCache {
  AvatarCache._();

  static const _maxBytes = 2 * 1024 * 1024;
  static const _memoryLimit = 200;

  // 這次開 App 已經讀過的（網址 → 圖片），用完最舊的先丟
  static final _memory = <String, Uint8List>{};
  // 這次開 App 已經向網路更新過的網址（不論成功），同一張不重複下載
  static final _refreshed = <String>{};
  static final _inFlight = <String, Future<Uint8List?>>{};
  static Future<Directory?>? _dir;

  /// 下載用的函式（測試時換成假的）
  @visibleForTesting
  static Future<http.Response> Function(Uri uri) fetch = http.get;

  /// 記憶體裡已經有的（畫面第一次 build 就能直接顯示）
  static Uint8List? peek(String url) => _memory[url];

  /// 先回傳暫存（記憶體或檔案），沒有就下載；onUpdate 會在背景下載到新版時呼叫
  static Future<Uint8List?> load(String url, {void Function(Uint8List bytes)? onUpdate}) async {
    final cached = _memory[url] ?? await _readFile(url);
    if (cached != null) {
      _remember(url, cached);
      if (!_refreshed.contains(url)) {
        unawaited(_download(url).then((fresh) {
          if (fresh != null && onUpdate != null) onUpdate(fresh);
        }));
      }
      return cached;
    }
    return _download(url);
  }

  /// 登出時清掉（記憶體與檔案）
  static Future<void> clear() async {
    _memory.clear();
    _refreshed.clear();
    try {
      final dir = await _directory();
      if (dir != null && await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {
      // 清不掉就算了，系統之後也會清暫存
    }
  }

  static Future<Uint8List?> _download(String url) {
    if (_refreshed.contains(url)) return Future.value(_memory[url]);
    return _inFlight[url] ??= () async {
      try {
        final uri = Uri.tryParse(url);
        if (uri == null || !(uri.isScheme('https') || uri.isScheme('http'))) return null;
        final res = await fetch(uri).timeout(const Duration(seconds: 15));
        final type = res.headers['content-type'] ?? '';
        final bytes = res.bodyBytes;
        if (res.statusCode != 200 || !type.startsWith('image/') || bytes.isEmpty || bytes.length > _maxBytes) return null;
        _refreshed.add(url);
        final unchanged = _memory[url] != null && _sameBytes(_memory[url]!, bytes);
        _remember(url, bytes);
        if (!unchanged) unawaited(_writeFile(url, bytes));
        return unchanged ? null : bytes;
      } catch (_) {
        // 離線、逾時：沿用暫存
        return null;
      } finally {
        unawaited(Future(() => _inFlight.remove(url)));
      }
    }();
  }

  static void _remember(String url, Uint8List bytes) {
    _memory.remove(url);
    _memory[url] = bytes;
    while (_memory.length > _memoryLimit) {
      _memory.remove(_memory.keys.first);
    }
  }

  static bool _sameBytes(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static Future<Directory?> _directory() => _dir ??= () async {
        try {
          return Directory('${(await getApplicationCacheDirectory()).path}/avatars');
        } catch (_) {
          return null;
        }
      }();

  static Future<File?> _file(String url) async {
    final dir = await _directory();
    return dir == null ? null : File('${dir.path}/${sha256.convert(utf8.encode(url))}');
  }

  static Future<Uint8List?> _readFile(String url) async {
    try {
      final file = await _file(url);
      if (file == null || !await file.exists()) return null;
      final bytes = await file.readAsBytes();
      return bytes.isEmpty ? null : bytes;
    } catch (_) {
      return null;
    }
  }

  static Future<void> _writeFile(String url, Uint8List bytes) async {
    try {
      final file = await _file(url);
      if (file == null) return;
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes, flush: true);
    } catch (_) {
      // 寫不進去就只留在記憶體
    }
  }
}
