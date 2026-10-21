import 'dart:io' show Platform;

import 'package:flutter/services.dart';

/*
 * 截圖與多工畫面的保護，由各平台原生程式處理（channel：securibit/privacy）：
 * - Android：FLAG_SECURE 擋住截圖、錄影與多工畫面縮圖；Android 13 以上只隱藏多工畫面時改用 setRecentsScreenshotEnabled
 * - iOS：沒有公開的 API 能擋截圖，只能在錄影、鏡像輸出時遮住畫面，進多工畫面前蓋上隱私畫面
 * - macOS：NSWindow.sharingType = .none，視窗不出現在截圖、錄影與螢幕分享
 * - Linux：無法阻擋
 */
class ScreenPrivacy {
  ScreenPrivacy._();

  static const _channel = MethodChannel('securibit/privacy');

  /// 這個平台能不能（至少部分）阻擋截圖
  static bool get canBlockCapture => Platform.isAndroid || Platform.isIOS || Platform.isMacOS;

  /// 設定頁「允許截圖」下方的說明，照實寫出這個平台做得到什麼
  static String get description {
    if (Platform.isAndroid) return '關閉時無法截圖或錄影，多工畫面也不會顯示驗證碼';
    if (Platform.isIOS) return 'iPhone 和 iPad 無法阻擋截圖；關閉時，錄影或鏡像輸出會遮住畫面，多工畫面也不會顯示驗證碼';
    if (Platform.isMacOS) return '關閉時視窗不會出現在系統截圖、錄影與螢幕分享中，但部分第三方錄影軟體可能仍拍得到';
    return 'Linux 無法阻擋截圖或錄影，請留意畫面上的驗證碼';
  }

  static (bool, bool)? _applied;

  /// blockCapture：不允許截圖；hideInSwitcher：多工畫面（App 切換器）不顯示內容
  static Future<void> apply({required bool blockCapture, required bool hideInSwitcher}) async {
    if (!canBlockCapture) return;
    final next = (blockCapture, hideInSwitcher);
    if (_applied == next) return;
    _applied = next;
    try {
      await _channel.invokeMethod<void>('configure', {'blockCapture': blockCapture, 'hideInSwitcher': hideInSwitcher});
    } on MissingPluginException {
      // 測試環境沒有原生端
    } on PlatformException {
      _applied = null;
    }
  }
}
