import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:securibit/core/rpc.dart';
import 'package:securibit/features/auth/refresh_guard_client.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _authUrl = 'https://example.supabase.co/auth/v1';

String _segment(Map<String, dynamic> json) => base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll('=', '');

// 只要 exp 正確的假 JWT（gotrue 從 access token 讀過期時間）
String _jwt(DateTime expiresAt) =>
    '${_segment({'alg': 'HS256', 'typ': 'JWT'})}.${_segment({'sub': 'u1', 'exp': expiresAt.millisecondsSinceEpoch ~/ 1000})}.sig';

Map<String, dynamic> _session(DateTime expiresAt, String refreshToken) => {
      'access_token': _jwt(expiresAt),
      'token_type': 'bearer',
      'expires_in': 3600,
      'refresh_token': refreshToken,
      'user': {
        'id': 'u1',
        'aud': 'authenticated',
        'app_metadata': <String, dynamic>{},
        'user_metadata': <String, dynamic>{},
        'created_at': '2024-01-01T00:00:00Z',
      },
    };

http.Response _json(int status, Object body) => http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

/// 帶著已過期 session 的 GoTrueClient；換新 token 的請求一律回 respond 的結果
Future<(GoTrueClient, List<AuthChangeEvent>)> _expiredClient(http.Response Function() respond, {bool guard = true}) async {
  final mock = MockClient((request) async => respond());
  final client = GoTrueClient(url: _authUrl, autoRefreshToken: false, httpClient: guard ? RefreshGuardClient(mock) : mock);
  await client.setInitialSession(jsonEncode(_session(DateTime.now().subtract(const Duration(hours: 2)), 'old-refresh')));
  final events = <AuthChangeEvent>[];
  client.onAuthStateChange.listen((state) => events.add(state.event), onError: (Object _) {});
  return (client, events);
}

void main() {
  group('shouldPassRefreshResponse', () {
    List<int> body(Object json) => utf8.encode(jsonEncode(json));

    test('伺服器明確拒絕 refresh token 時原樣交回（會登出）', () {
      for (final code in ['refresh_token_not_found', 'refresh_token_already_used', 'session_not_found', 'session_expired', 'user_banned']) {
        expect(shouldPassRefreshResponse(400, body({'code': code, 'msg': 'Invalid Refresh Token'})), isTrue, reason: code);
      }
      expect(shouldPassRefreshResponse(400, body({'error_code': 'refresh_token_not_found'})), isTrue);
      expect(shouldPassRefreshResponse(400, body({'error': 'invalid_grant', 'error_description': 'Invalid Refresh Token'})), isTrue);
    });

    test('其他失敗當成暫時的（保留 session）', () {
      expect(shouldPassRefreshResponse(429, body({'code': 'over_request_rate_limit', 'msg': 'Too many requests'})), isFalse);
      expect(shouldPassRefreshResponse(403, utf8.encode('<html>Access denied</html>')), isFalse);
      expect(shouldPassRefreshResponse(400, const []), isFalse);
      expect(shouldPassRefreshResponse(408, body({'message': 'timeout'})), isFalse);
      expect(shouldPassRefreshResponse(401, body({'message': 'Invalid API key'})), isFalse);
      expect(shouldPassRefreshResponse(200, body({'message': 'ok'})), isFalse);
      expect(shouldPassRefreshResponse(200, utf8.encode('<html>portal</html>')), isFalse);
    });

    test('成功帶著新 token、或 5xx 時原樣交回', () {
      expect(shouldPassRefreshResponse(200, body({'access_token': 'a', 'refresh_token': 'r'})), isTrue);
      expect(shouldPassRefreshResponse(502, utf8.encode('Bad gateway')), isTrue);
    });
  });

  group('RefreshGuardClient', () {
    test('只改換新 token 的請求', () async {
      final client = RefreshGuardClient(MockClient((request) async => http.Response('<html></html>', 403)));
      final refresh = await client.post(Uri.parse('$_authUrl/token?grant_type=refresh_token'));
      expect(refresh.statusCode, 503);
      expect(refresh.body, '<html></html>');
      final password = await client.post(Uri.parse('$_authUrl/token?grant_type=password'));
      expect(password.statusCode, 403);
      final rest = await client.get(Uri.parse('https://example.supabase.co/rest/v1/profiles'));
      expect(rest.statusCode, 403);
    });
  });

  group('換新 token 失敗時的登入狀態', () {
    test('沒有保護時，429 會直接登出（原本的問題）', () async {
      final (client, events) = await _expiredClient(() => _json(429, {'code': 'over_request_rate_limit', 'msg': 'Too many requests'}), guard: false);
      await expectLater(client.refreshSession(), throwsA(isA<AuthApiException>()));
      await pumpEventQueue();
      expect(client.currentSession, isNull);
      expect(events, contains(AuthChangeEvent.signedOut));
    });

    test('有保護時，429 保留 session，之後再試', () async {
      final (client, events) = await _expiredClient(() => _json(429, {'code': 'over_request_rate_limit', 'msg': 'Too many requests'}));
      await expectLater(client.refreshSession(), throwsA(isA<AuthRetryableFetchException>()));
      await pumpEventQueue();
      expect(client.currentSession?.refreshToken, 'old-refresh');
      expect(events, isNot(contains(AuthChangeEvent.signedOut)));
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('有保護時，refresh token 被撤銷一樣登出', () async {
      final (client, events) = await _expiredClient(() => _json(400, {'code': 'refresh_token_not_found', 'msg': 'Invalid Refresh Token: Refresh Token Not Found'}));
      await expectLater(client.refreshSession(), throwsA(isA<AuthApiException>()));
      await pumpEventQueue();
      expect(client.currentSession, isNull);
      expect(events, contains(AuthChangeEvent.signedOut));
    });

    test('有保護時，換新成功照常更新 session', () async {
      final fresh = _session(DateTime.now().add(const Duration(hours: 1)), 'new-refresh');
      final (client, events) = await _expiredClient(() => _json(200, fresh));
      final response = await client.refreshSession();
      await pumpEventQueue();
      expect(response.session?.refreshToken, 'new-refresh');
      expect(client.currentSession?.refreshToken, 'new-refresh');
      expect(events, contains(AuthChangeEvent.tokenRefreshed));
    });
  });

  test('token 暫時換不到新的，讀資料的錯誤算離線（改用離線快取）', () {
    final result = errorResult<void>(AuthRetryableFetchException(message: 'Too many requests', statusCode: '503'));
    expect(result.offline, isTrue);
    expect(result.message, offlineMessage);
  });
}
