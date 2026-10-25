import 'package:flutter/foundation.dart';

/*
 * 點了推播或系統通知、等著打開的畫面（見 NotificationHost）：App 鎖著時等解鎖、還沒登入時等登入。
 * 只留最新的一個；link 是站內路徑，空字串是打開收件匣。
 */
class NotificationLinkQueue extends ChangeNotifier {
  String? _pending;

  bool get hasPending => _pending != null;

  void push(String link) {
    _pending = link;
    notifyListeners();
  }

  /// 取出等著的連結（沒有時是 null）
  String? take() {
    final link = _pending;
    _pending = null;
    return link;
  }

  void clear() => _pending = null;
}
