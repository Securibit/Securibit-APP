import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/result.dart';
import '../../core/rpc.dart';
import '../cache/offline_cache.dart';
import 'auth_repository.dart' as repo;
import 'native_google_sign_in.dart';
import 'oauth_redirect.dart';
import 'profile.dart';

enum AuthStatus { loading, signedOut, signedIn }

/*
 * 登入狀態：全 App 只訂閱一次 Supabase 的 onAuthStateChange。
 * 登入後先 ensure_profile 再讀 profile；連不上時改用離線快取的 profile，讓驗證碼還能顯示。
 */
class AuthController extends ChangeNotifier {
  AuthController({required this.cache, required this.onSignedIn, required this.onSignedOut});

  final OfflineCache cache;
  // 拿到 profile 後通知其他狀態（加密、群組）
  final void Function(Profile profile) onSignedIn;
  final void Function(String? uid) onSignedOut;

  AuthStatus status = AuthStatus.loading;
  Profile? profile;
  // 載入 profile 失敗的原因（顯示在畫面上，可以重試）
  String? profileError;
  bool signingIn = false;

  StreamSubscription<AuthState>? _subscription;
  OAuthRedirect? _redirect;
  String? _loadedUid;

  User? get user => supabase.auth.currentUser;

  // 手機有設定 Google 用戶端 ID 時用原生帳號選單，否則開瀏覽器登入
  bool get usesBrowser => !NativeGoogleSignIn.isAvailable;

  void start() {
    _subscription = supabase.auth.onAuthStateChange.listen(
      (state) {
        final sessionUser = state.session?.user;
        if (sessionUser == null) {
          _handleSignedOut();
          return;
        }
        // 剛完成登入（不是開 App 時還原的 session）才記一次登入紀錄
        if (state.event == AuthChangeEvent.signedIn && signingIn) {
          signingIn = false;
          unawaited(repo.recordLogin());
        }
        status = AuthStatus.signedIn;
        notifyListeners();
        if (_loadedUid != sessionUser.id) {
          _loadedUid = sessionUser.id;
          unawaited(loadProfile());
        } else if (state.event == AuthChangeEvent.tokenRefreshed && profile == null && profileError != null) {
          // 剛才 token 過期、讀不到使用者資料；換到新的 token 後自動再讀一次，不用停在錯誤畫面
          unawaited(loadProfile());
        }
      },
      onError: (Object error) {
        // 深層連結帶回來的錯誤（例如使用者取消）
        signingIn = false;
        profileError = null;
        if (status == AuthStatus.loading) status = AuthStatus.signedOut;
        notifyListeners();
      },
    );
  }

  void _handleSignedOut() {
    final uid = _loadedUid ?? profile?.uid;
    _loadedUid = null;
    profile = null;
    profileError = null;
    status = AuthStatus.signedOut;
    notifyListeners();
    onSignedOut(uid);
  }

  /// 讀取（或重新讀取）自己的 profile
  Future<void> loadProfile() async {
    final uid = user?.id;
    if (uid == null) return;
    profileError = null;
    notifyListeners();

    final ensured = await repo.ensureProfile();
    final result = ensured is Err<void> && ensured.offline ? Err<Profile>(ensured.message, offline: true) : await repo.loadProfile(uid);
    if (user?.id != uid) return;

    switch (result) {
      case Ok(:final data):
        profile = data;
        unawaited(cache.saveProfile(uid, data.toJson()));
        onSignedIn(data);
      case Err(:final message, :final offline):
        final cached = offline ? await cache.loadProfile(uid) : null;
        if (user?.id != uid) return;
        if (cached != null) {
          profile = Profile.fromJson(cached);
          onSignedIn(profile!);
        } else {
          profileError = message;
        }
    }
    notifyListeners();
  }

  /// 重新讀取自己的 profile（改了名稱、@ID、加密設定之後呼叫）；成功回傳 null，失敗回傳錯誤訊息並保留原本的資料
  Future<String?> refreshProfile() async {
    final uid = user?.id;
    if (uid == null) return '尚未登入';
    final result = await repo.loadProfile(uid);
    if (user?.id != uid) return null;
    switch (result) {
      case Ok(:final data):
        profile = data;
        profileError = null;
        unawaited(cache.saveProfile(uid, data.toJson()));
        onSignedIn(data);
        notifyListeners();
        return null;
      case Err(:final message):
        return message;
    }
  }

  /// Google 登入；回傳錯誤訊息（null 代表成功開始或使用者自己取消）
  Future<String?> signInWithGoogle() async {
    _redirect?.cancel();
    signingIn = true;
    notifyListeners();
    try {
      if (usesBrowser) {
        final redirect = OAuthRedirect.forPlatform();
        _redirect = redirect;
        await redirect.signIn(supabase.auth);
        // 深層連結版：瀏覽器已開啟，等 onAuthStateChange；使用者回到 App 沒登入時可以再按一次
      } else {
        // 原生版：回來時 session 已建立（onAuthStateChange 會收到 signedIn）
        await NativeGoogleSignIn.signIn(supabase.auth);
      }
      return null;
    } on OAuthRedirectException catch (error) {
      signingIn = false;
      notifyListeners();
      return error.cancelled ? null : error.message;
    } catch (error) {
      signingIn = false;
      notifyListeners();
      return errorResult<void>(error).message;
    }
  }

  /// 使用者回到登入頁按取消時，停止等待
  void cancelSignIn() {
    _redirect?.cancel();
    signingIn = false;
    notifyListeners();
  }

  /// 登出：撤銷這台裝置的 session，清掉離線快取與記住的加密金鑰
  Future<String?> signOut() async {
    final uid = profile?.uid ?? user?.id;
    try {
      await supabase.auth.signOut();
    } catch (error) {
      // 連不上伺服器時仍清掉本機的 session（Supabase 會自己移除）
      final result = errorResult<void>(error);
      if (!result.offline) return result.message;
    }
    if (uid != null) await cache.clear(uid);
    await NativeGoogleSignIn.signOut();
    if (status != AuthStatus.signedOut) _handleSignedOut();
    return null;
  }

  /// 刪除自己的帳戶（網站的 /api/delete-account）；成功後登出並清掉這台裝置的快取。回傳錯誤訊息，成功為 null
  Future<String?> deleteAccount() async {
    final uid = profile?.uid ?? user?.id;
    final result = await repo.deleteAccount();
    if (result case Err(:final message)) return message;
    // 帳戶已經不在：伺服器端的登出可能失敗，本機的 session 一樣會先移除
    try {
      await supabase.auth.signOut();
    } catch (_) {
      // 忽略
    }
    if (uid != null) await cache.clear(uid);
    await NativeGoogleSignIn.signOut();
    if (status != AuthStatus.signedOut) _handleSignedOut();
    return null;
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _redirect?.cancel();
    super.dispose();
  }
}
