import 'package:flutter/foundation.dart';

/*
 * macOS 選單列常駐時，關掉主視窗只是把它藏起來（App 還在跑），系統的生命週期不一定會變成 hidden。
 * 原生端在藏起、重新顯示主視窗時通知這裡，App 鎖定把藏起來當成離開 App、顯示當成回來。
 */
class WindowVisibility {
  WindowVisibility._();

  static final visible = ValueNotifier<bool>(true);
}
