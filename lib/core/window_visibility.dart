import 'package:flutter/foundation.dart';

/*
 * macOS 選單列、Linux 與 Windows 系統匣常駐時，關掉主視窗只是把它藏起來（App 還在跑），系統的生命週期不一定會變成 hidden。
 * 原生端在藏起、重新顯示主視窗時通知這裡，App 鎖定把藏起來當成離開 App、顯示當成回來。
 * Windows 登入時自動開啟（帶 --hidden）時，主視窗一開始就藏在系統匣（見 launchedHidden）。
 */
class WindowVisibility {
  WindowVisibility._();

  static final visible = ValueNotifier<bool>(true);

  /// Windows 登入時自動開啟帶的參數（登錄檔的 Run 值）；和 windows/runner/app_window.h 的 kHiddenArgument 相同
  static const hiddenArgument = '--hidden';

  /// 命令列有 --hidden：原生端不顯示主視窗，等使用者從系統匣叫出來（叫出來時原生端送 windowDidShow）
  static bool launchedHidden(List<String> args) => args.contains(hiddenArgument);
}
