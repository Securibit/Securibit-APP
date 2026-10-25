import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart' show MediaType;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'env.dart';
import 'platform.dart';
import 'result.dart';

SupabaseClient get supabase => Supabase.instance.client;

// 函式不存在（資料庫還沒執行對應的 migration）
const _missingFunction = 'PGRST202';
const offlineMessage = '無法連線到伺服器，請檢查網路連線';

bool _isNetworkError(Object error) =>
    error is SocketException || error is http.ClientException || error is TimeoutException || error is HandshakeException;

/// 把例外轉成給使用者看的中文訊息（資料庫的 raise exception 本來就是中文，直接用）
Err<T> errorResult<T>(Object error, {String? function}) {
  if (_isNetworkError(error)) return Err<T>(offlineMessage, offline: true);
  if (error is PostgrestException) {
    if (error.code == _missingFunction) {
      return Err<T>('資料庫還沒有「${function ?? '這個'}」功能，請先更新網站的資料庫');
    }
    return Err<T>(error.message);
  }
  if (error is AuthException) {
    // 登入 token 過期又暫時換不到新的（沒網路、伺服器忙）：當成離線，改用離線快取，不要擋在錯誤畫面
    final offline = error is AuthRetryableFetchException || _isNetworkMessage(error.message);
    return offline ? Err<T>(offlineMessage, offline: true) : Err<T>(error.message);
  }
  return Err<T>('發生錯誤：$error');
}

bool _isNetworkMessage(String message) =>
    message.contains('SocketException') || message.contains('ClientException') || message.contains('Failed host lookup');

/// 呼叫 RPC，解析成 T；資料庫回傳 null 時交給 parse 處理
Future<Result<T>> rpc<T>(String fn, T Function(dynamic data) parse, [Map<String, dynamic>? params]) async {
  try {
    final data = await supabase.rpc(fn, params: params).timeout(const Duration(seconds: 20));
    return Ok(parse(data));
  } catch (error) {
    return errorResult<T>(error, function: fn);
  }
}

/// 不需要回傳值的 RPC
Future<Result<void>> rpcVoid(String fn, [Map<String, dynamic>? params]) => rpc<void>(fn, (_) {}, params);

/// 網站要求重新登入才能做的操作（刪除帳戶等）回傳的錯誤代碼
const reauthRequiredCode = 'reauth_required';

/// 帶著目前的登入 token 呼叫網站的 API route（同網站的 callApi）
Future<Result<Map<String, dynamic>>> callWebApi(String path, Object? body) => _sendWebApi(
      (token) => http.post(
        Uri.parse('${Env.webUrl}$path'),
        headers: {..._webHeaders(token), 'Content-Type': 'application/json'},
        body: jsonEncode(body ?? {}),
      ),
    );

/// DELETE 網站的 API route（query 是網址參數）
Future<Result<Map<String, dynamic>>> deleteWebApi(String path, Map<String, String> query) => _sendWebApi(
      (token) => http.delete(Uri.parse('${Env.webUrl}$path').replace(queryParameters: query), headers: _webHeaders(token)),
    );

/// 用 multipart/form-data 上傳檔案到網站的 API route（fields 是其他欄位；上傳比較久，逾時放寬）
Future<Result<Map<String, dynamic>>> uploadWebApi(
  String path, {
  required String field,
  required List<int> bytes,
  required String filename,
  required String contentType,
  Map<String, String> fields = const {},
}) =>
    _sendWebApi(
      (token) async {
        final request = http.MultipartRequest('POST', Uri.parse('${Env.webUrl}$path'))
          ..headers.addAll(_webHeaders(token))
          ..fields.addAll(fields)
          ..files.add(http.MultipartFile.fromBytes(field, bytes, filename: filename, contentType: MediaType.parse(contentType)));
        return http.Response.fromStream(await request.send());
      },
      timeout: const Duration(seconds: 60),
    );

Map<String, String> _webHeaders(String token) => {'Authorization': 'Bearer $token', 'User-Agent': AppPlatform.userAgent};

// 錯誤是 { error, code? }（舊的 API 是 { message }）；不是 JSON（例如網站錯誤頁）就當作沒有內容
Future<Result<Map<String, dynamic>>> _sendWebApi(
  Future<http.Response> Function(String token) send, {
  Duration timeout = const Duration(seconds: 15),
}) async {
  final session = supabase.auth.currentSession;
  if (session == null) return const Err('尚未登入');
  try {
    final res = await send(session.accessToken).timeout(timeout);
    Map<String, dynamic> json = {};
    try {
      final decoded = jsonDecode(utf8.decode(res.bodyBytes));
      if (decoded is Map<String, dynamic>) json = decoded;
    } catch (_) {
      // 沒有內容
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      final message = json['error'] ?? json['message'];
      return Err(message is String && message.isNotEmpty ? message : '請求失敗（${res.statusCode}）', code: json['code'] as String?);
    }
    return Ok(json);
  } catch (error) {
    return _isNetworkError(error) ? const Err(offlineMessage, offline: true) : Err('無法連線到網站：$error');
  }
}
