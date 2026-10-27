import 'package:flutter/services.dart';

/// Google Play 立即更新的結果（見 android/.../PlayUpdate.kt）
enum PlayUpdateOutcome {
  // Play 開始安裝（通常 App 會直接被重新開啟）
  ok,
  // 使用者關掉了 Google Play 的畫面
  canceled,
  // Google Play 還不知道有新版，或不是從 Google Play 安裝的
  unavailable,
  // 查詢或開啟失敗
  failed,
}

/*
 * Google Play 版的強制更新：版本低於後台的最低版本時（ForcedUpdatePage），
 * 打開 Google Play 的「有可用的更新」畫面，由商店下載、安裝並重新開啟 App。
 */
class PlayUpdate {
  static const _channel = MethodChannel('securibit/update');

  static Future<PlayUpdateOutcome> start() async {
    try {
      final name = await _channel.invokeMethod<String>('playUpdate');
      return PlayUpdateOutcome.values.firstWhere((o) => o.name == name, orElse: () => PlayUpdateOutcome.failed);
    } catch (_) {
      return PlayUpdateOutcome.failed;
    }
  }
}
