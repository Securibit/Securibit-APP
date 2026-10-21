import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
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
    return _isNetworkMessage(error.message) ? Err<T>(offlineMessage, offline: true) : Err<T>(error.message);
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

/// 帶著目前的登入 token 呼叫網站的 API route（同網站的 callApi）
Future<Result<Map<String, dynamic>>> callWebApi(String path, Object? body) async {
  final session = supabase.auth.currentSession;
  if (session == null) return const Err('尚未登入');
  try {
    final res = await http
        .post(
          Uri.parse('${Env.webUrl}$path'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${session.accessToken}',
            'User-Agent': AppPlatform.userAgent,
          },
          body: jsonEncode(body ?? {}),
        )
        .timeout(const Duration(seconds: 15));
    Map<String, dynamic> json = {};
    try {
      final decoded = jsonDecode(utf8.decode(res.bodyBytes));
      if (decoded is Map<String, dynamic>) json = decoded;
    } catch (_) {
      // 不是 JSON（例如網站錯誤頁）就當作沒有內容
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      return Err(json['message'] as String? ?? '請求失敗（${res.statusCode}）');
    }
    return Ok(json);
  } catch (error) {
    return _isNetworkError(error) ? const Err(offlineMessage, offline: true) : Err('無法連線到網站：$error');
  }
}
