import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show PlatformException;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../menubar/desktop_tray.dart';

/*
 * Google 登入（PKCE）怎麼把結果帶回 App：
 * - iOS / Android：系統瀏覽器登入後轉向 securibit://login-callback，
 *   supabase_flutter 透過 app_links 收到連結，自己換成 session（onAuthStateChange 會收到 signedIn）。
 * - macOS / Linux / Windows：在 127.0.0.1 開一個暫時的 HTTP 伺服器接 ?code=，再換成 session。
 *   瀏覽器停在「登入完成，可以關閉此頁面」，App 自己回到前景
 *   （深層連結版的分頁會停在空白頁；Linux 的自訂 scheme 也不可靠）。
 * 兩個轉向網址都要加進 Supabase Auth → URL Configuration 的 Redirect URLs。
 */
abstract class OAuthRedirect {
  const OAuthRedirect();

  factory OAuthRedirect.forPlatform() =>
      Platform.isMacOS || Platform.isLinux || Platform.isWindows ? LoopbackOAuthRedirect() : const DeepLinkOAuthRedirect();

  /// 開啟瀏覽器登入。深層連結版在瀏覽器開啟後就結束；本機伺服器版會等到 session 建立。
  /// 失敗時丟出 OAuthRedirectException（訊息是中文）
  Future<void> signIn(GoTrueClient auth);

  /// 使用者取消或關掉 App 前，停止等待
  void cancel() {}
}

class OAuthRedirectException implements Exception {
  const OAuthRedirectException(this.message, {this.cancelled = false});
  final String message;
  // 使用者在 Google 頁面按取消，不算錯誤
  final bool cancelled;

  @override
  String toString() => message;
}

// 每次都讓使用者選帳號，方便切換 Google 帳號（同網站）
const _queryParams = {'prompt': 'select_account'};

class DeepLinkOAuthRedirect extends OAuthRedirect {
  const DeepLinkOAuthRedirect();

  static const redirectUrl = 'securibit://login-callback';

  @override
  Future<void> signIn(GoTrueClient auth) async {
    final bool opened;
    try {
      opened = await auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: redirectUrl,
        authScreenLaunchMode: LaunchMode.externalApplication,
        queryParams: _queryParams,
      );
    } on PlatformException {
      // 例如 Android 沒有可用的瀏覽器（ACTIVITY_NOT_FOUND）
      throw const OAuthRedirectException('無法開啟瀏覽器，請確認裝置有可用的瀏覽器');
    }
    if (!opened) throw const OAuthRedirectException('無法開啟瀏覽器');
  }
}

class LoopbackOAuthRedirect extends OAuthRedirect {
  LoopbackOAuthRedirect();

  static const callbackPath = '/login-callback';
  // 等使用者在瀏覽器登入的時間上限
  static const timeout = Duration(minutes: 5);

  HttpServer? _server;

  @override
  Future<void> signIn(GoTrueClient auth) async {
    cancel();
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server = server;
    try {
      final redirectTo = 'http://127.0.0.1:${server.port}$callbackPath';
      final res = await auth.getOAuthSignInUrl(provider: OAuthProvider.google, redirectTo: redirectTo, queryParams: _queryParams);
      if (!await launchUrl(Uri.parse(res.url), mode: LaunchMode.externalApplication)) {
        throw const OAuthRedirectException('無法開啟瀏覽器');
      }

      final params = await _waitForCallback(server).timeout(
        timeout,
        onTimeout: () => throw const OAuthRedirectException('登入逾時，請再試一次'),
      );
      final error = params['error'];
      if (error != null) {
        if (error == 'access_denied') throw const OAuthRedirectException('已取消登入', cancelled: true);
        throw OAuthRedirectException(params['error_description'] ?? error);
      }
      final code = params['code'];
      if (code == null || code.isEmpty) throw const OAuthRedirectException('沒有取得登入資訊，請再試一次');
      await auth.exchangeCodeForSession(code);
      // 使用者還在瀏覽器，把 App 叫回前景
      await DesktopTray.showWindow();
    } on StateError {
      throw const OAuthRedirectException('已取消登入', cancelled: true);
    } finally {
      cancel();
    }
  }

  // 只處理 callback 路徑（瀏覽器可能順便要 /favicon.ico），回一頁請使用者回到 App
  Future<Map<String, String>> _waitForCallback(HttpServer server) async {
    await for (final request in server) {
      if (request.uri.path != callbackPath) {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        continue;
      }
      final params = request.uri.queryParameters;
      final ok = params['error'] == null;
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.html
        ..add(utf8.encode(_page(ok ? '登入完成' : '登入沒有完成', ok ? '可以關閉此頁面，回到 Securibit' : '可以關閉此頁面，回到 Securibit 再試一次')));
      await request.response.close();
      return params;
    }
    throw StateError('closed');
  }

  @override
  void cancel() {
    _server?.close(force: true);
    _server = null;
  }

  String _page(String title, String message) => '''
<!doctype html><html lang="zh-Hant"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width">
<title>$title</title>
<style>
body{margin:0;min-height:100vh;display:flex;align-items:center;justify-content:center;font-family:system-ui,-apple-system,"Noto Sans TC",sans-serif;background:#fff;color:#1D1D1F}
@media (prefers-color-scheme:dark){body{background:#1C1C1E;color:#F5F5F7}p{color:#A8A8AE}}
h1{font-size:22px;font-weight:600;margin:0 0 6px}p{font-size:17px;color:#6E6E73;margin:0}
</style></head><body><div><h1>$title</h1><p>$message</p></div></body></html>''';
}
