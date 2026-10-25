import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  // 打開選單列時關掉視窗不結束（常駐在選單列），⌘Q 或選單的「結束 Securibit」才結束；關掉選單列時同一般 App
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return !MenuBarController.shared.isEnabled
  }

  // 點 Dock 圖示（或再打開一次 App）時叫回藏起來的主視窗
  override func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    MenuBarController.shared.showMainWindow()
    return false
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  // 結束時有下載好的更新就啟動替換腳本（見 AppUpdate）。
  // 不呼叫 super：FlutterAppDelegate 實際上沒有實作這個方法，呼叫會丟出 unrecognized selector
  override func applicationWillTerminate(_ notification: Notification) {
    AppUpdate.shared.launchPendingInstall()
  }
}
