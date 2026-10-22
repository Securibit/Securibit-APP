import 'dart:convert';

import 'package:http/http.dart' as http;

/*
 * 換新登入 token 的保護：只有伺服器明確說 refresh token 無效、已經用過、session 被撤銷或帳戶不能用時，才讓 Supabase 登出。
 * supabase 套件把 5xx 以外的失敗都當成 token 失效，直接登出並刪掉存著的 session，例如：
 * 429 太多請求、空白或不是 JSON 的錯誤頁（代理、防火牆、CDN）、成功卻沒有帶新的 token。
 * 這些回應改成 503 交回去，套件就當成連線問題：保留 session，之後自動重試。其他請求原封不動。
 */
class RefreshGuardClient extends http.BaseClient {
  RefreshGuardClient([http.Client? inner]) : _inner = inner ?? http.Client();

  final http.Client _inner;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = await _inner.send(request);
    if (!isRefreshRequest(request)) return response;

    // 讀到一半斷線會在這裡丟出例外，套件一樣當成連線問題
    final body = await response.stream.toBytes();
    final pass = shouldPassRefreshResponse(response.statusCode, body);
    return http.StreamedResponse(
      http.ByteStream.fromBytes(body),
      pass ? response.statusCode : 503,
      contentLength: body.length,
      request: response.request,
      headers: response.headers,
      isRedirect: response.isRedirect,
      persistentConnection: response.persistentConnection,
      reasonPhrase: pass ? response.reasonPhrase : 'Service Unavailable',
    );
  }

  @override
  void close() => _inner.close();
}

// Supabase Auth 明確拒絕這個 refresh token 的錯誤碼（https://supabase.com/docs/guides/auth/debugging/error-codes）
const _rejectedCodes = {
  'refresh_token_not_found',
  'refresh_token_already_used',
  'session_not_found',
  'session_expired',
  'user_not_found',
  'user_banned',
};

/// 換新 token 的請求：POST /auth/v1/token?grant_type=refresh_token
bool isRefreshRequest(http.BaseRequest request) =>
    request.method == 'POST' &&
    request.url.path.endsWith('/auth/v1/token') &&
    request.url.queryParameters['grant_type'] == 'refresh_token';

/// 換新 token 的回應要不要原樣交給 Supabase：成功且帶著新的 token、伺服器錯誤（本來就會重試）、
/// 或伺服器明確拒絕這個 refresh token。其他都當成暫時的失敗
bool shouldPassRefreshResponse(int status, List<int> body) {
  if (status >= 500) return true;
  final json = _decode(body);
  if (status >= 200 && status < 300) return json?['access_token'] is String;
  if (json == null) return false;
  final code = json['code'] ?? json['error_code'];
  if (code is String) return _rejectedCodes.contains(code);
  // 舊版 Auth 沒有錯誤碼，refresh token 無效時回 invalid_grant
  return json['error'] == 'invalid_grant';
}

Map<String, dynamic>? _decode(List<int> body) {
  try {
    final value = jsonDecode(utf8.decode(body));
    return value is Map<String, dynamic> ? value : null;
  } catch (_) {
    return null;
  }
}
