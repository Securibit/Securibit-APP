import 'package:flutter/foundation.dart';

import '../../core/env.dart';
import 'deep_link.dart';

/// 已選好群組、等那個群組的驗證碼清單準備好才打開新增表單（見 CodeLinkHost）
class CodeRequest {
  const CodeRequest(this.groupId, this.text);

  final String groupId;
  final String text;
}

/*
 * 收到的連結排隊等可以處理的時候（見 DeepLinkHost）：
 * - 還沒登入：留著，登入完成、主畫面出來後再打開
 * - App 鎖定中：留著，解鎖後再打開
 * 只留最新的一個（連點兩次不同的連結，以最後一次為準）；只放在記憶體，關掉 App 就沒了。
 * 同一個連結短時間內收到兩次（app_links 的初始連結與串流各給一次）只算一次。
 */
class DeepLinkController extends ChangeNotifier {
  DeepLinkController({this.webUrl = Env.webUrl, DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final String webUrl;
  final DateTime Function() _clock;

  // 同一個連結在這段時間內再收到就略過
  static const duplicateWindow = Duration(seconds: 3);

  DeepLink? _pending;
  CodeRequest? _codeRequest;
  String? _lastRaw;
  DateTime? _lastAt;

  /// 等著打開的連結
  DeepLink? get pending => _pending;

  /// 已選好群組的新增驗證碼
  CodeRequest? get codeRequest => _codeRequest;

  /// 解析收到的連結；不用處理（登入轉回來的、重複的）時回傳 null。還不排隊，見 [queue]
  DeepLink? accept(String raw) {
    final now = _clock();
    final text = raw.trim();
    final last = _lastAt;
    if (text == _lastRaw && last != null && now.difference(last) < duplicateWindow) return null;
    final link = parseDeepLink(text, webUrl: webUrl);
    if (link == null) return null;
    _lastRaw = text;
    _lastAt = now;
    return link;
  }

  /// 排入要打開的連結（錯誤的連結不排，直接顯示錯誤）
  void queue(DeepLink link) {
    if (link is InvalidLink) return;
    _pending = link;
    notifyListeners();
  }

  /// accept + queue；回傳解析結果
  DeepLink? receive(String raw) {
    final link = accept(raw);
    if (link != null) queue(link);
    return link;
  }

  /// 可以處理時取出等著的連結：要已登入（主畫面出來了）而且沒有鎖定
  DeepLink? takeIfReady({required bool signedIn, required bool locked}) {
    if (!signedIn || locked) return null;
    final link = _pending;
    _pending = null;
    return link;
  }

  /// 選好群組後，等那個群組的清單準備好再打開表單
  void requestCode(String groupId, String text) {
    _codeRequest = CodeRequest(groupId, text);
    notifyListeners();
  }

  /// 這個群組的清單準備好了：取出要新增的內容（不是這個群組的就不動）
  CodeRequest? takeCodeRequest(String groupId) {
    final request = _codeRequest;
    if (request == null || request.groupId != groupId) return null;
    _codeRequest = null;
    return request;
  }

  /// 登出時清掉已經選好群組的請求（等著的連結留著，下次登入後打開）
  void clearCodeRequest() => _codeRequest = null;
}
