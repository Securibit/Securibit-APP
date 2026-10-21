import 'dart:io' show Platform;

import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/env.dart';
import 'oauth_redirect.dart';

/*
 * iOS / Android 的原生 Google 登入：App 內直接跳出 Google 帳號選單，不開瀏覽器。
 * 拿到 Google 的 idToken 後交給 supabase.auth.signInWithIdToken 換成 session。
 * - Android 走 Credential Manager，idToken 的 audience 是 serverClientId（網頁用戶端）
 * - iOS 走 GoogleSignIn SDK，idToken 的 audience 是 iOS 用戶端；SDK 會自己在 idToken 放 nonce，
 *   所以 Supabase 的 Google provider 要開「Skip nonce check」（Supabase 文件的建議做法）
 * 三個用戶端 ID 都要加進 Supabase Google provider 的 Authorized Client IDs。
 * 沒有設定用戶端 ID 時 isAvailable 為 false，改用瀏覽器登入。
 */
class NativeGoogleSignIn {
  NativeGoogleSignIn._();

  static const _scopes = ['email', 'profile'];

  // initialize 只能呼叫一次，第一次登入時才初始化
  static Future<void>? _initializing;

  static bool get isAvailable {
    if (Platform.isAndroid) return Env.googleWebClientId.isNotEmpty;
    if (Platform.isIOS) return Env.googleIosClientId.isNotEmpty && Env.googleWebClientId.isNotEmpty;
    return false;
  }

  static Future<void> _ensureInitialized() => _initializing ??= _initialize();

  static Future<void> _initialize() async {
    try {
      await GoogleSignIn.instance.initialize(
        clientId: Platform.isIOS ? Env.googleIosClientId : null,
        serverClientId: Env.googleWebClientId,
      );
    } catch (_) {
      // 初始化失敗時下次再試
      _initializing = null;
      rethrow;
    }
  }

  /// 跳出 Google 帳號選單並登入 Supabase；失敗時丟出 OAuthRedirectException（訊息是中文）
  static Future<void> signIn(GoTrueClient auth) async {
    try {
      await _ensureInitialized();
      final account = await GoogleSignIn.instance.authenticate(scopeHint: _scopes);
      final idToken = account.authentication.idToken;
      if (idToken == null || idToken.isEmpty) throw const OAuthRedirectException('沒有取得 Google 登入資訊，請再試一次');

      // 照 Supabase 文件一併帶 accessToken；email、profile 在登入時已授權，通常不會再跳畫面
      final client = account.authorizationClient;
      final authorization = await client.authorizationForScopes(_scopes) ?? await client.authorizeScopes(_scopes);

      await auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
        accessToken: authorization.accessToken,
      );
    } on GoogleSignInException catch (error) {
      throw _translate(error);
    }
  }

  /// 登出 Supabase 後一併登出 Google，下次登入才能選別的帳號
  static Future<void> signOut() async {
    final initializing = _initializing;
    if (initializing == null) return;
    try {
      await initializing;
      await GoogleSignIn.instance.signOut();
    } catch (_) {
      // 只影響下次是否自動選同一個帳號，不影響登出
    }
  }

  static OAuthRedirectException _translate(GoogleSignInException error) => switch (error.code) {
        GoogleSignInExceptionCode.canceled => const OAuthRedirectException('已取消登入', cancelled: true),
        GoogleSignInExceptionCode.interrupted => const OAuthRedirectException('登入被中斷，請再試一次'),
        GoogleSignInExceptionCode.uiUnavailable => const OAuthRedirectException('無法顯示 Google 登入畫面，請再試一次'),
        GoogleSignInExceptionCode.clientConfigurationError ||
        GoogleSignInExceptionCode.providerConfigurationError =>
          OAuthRedirectException('Google 登入設定有誤，請確認 OAuth 用戶端設定（${error.description ?? error.code.name}）'),
        _ => OAuthRedirectException('Google 登入失敗：${error.description ?? error.code.name}'),
      };
}
