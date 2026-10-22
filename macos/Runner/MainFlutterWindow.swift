import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow, NSWindowDelegate {
  override func awakeFromNib() {
    // 關掉 App Sandbox 後第一次啟動：先把舊 container 的設定搬過來，Flutter 讀設定前就要搬好
    SandboxMigration.runIfNeeded()

    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController

    // 預設大小放得下三欄（側欄｜清單｜詳細資料），最小寬度收合成單欄
    let size = NSSize(width: 1180, height: 760)
    self.setContentSize(size)
    self.contentMinSize = NSSize(width: 400, height: 560)
    self.title = "Securibit"
    self.center()
    self.setFrameAutosaveName("SecuribitMainWindow")

    // 預設允許截圖：.none 會讓視窗在 Parsec、AnyDesk 等遠端桌面上也看不到；設定頁關掉「允許截圖」才改成 .none
    self.sharingType = .readOnly
    let privacy = FlutterMethodChannel(name: "securibit/privacy", binaryMessenger: flutterViewController.engine.binaryMessenger)
    privacy.setMethodCallHandler { [weak self] call, result in
      guard call.method == "configure" else {
        result(FlutterMethodNotImplemented)
        return
      }
      let args = call.arguments as? [String: Any]
      let block = args?["blockCapture"] as? Bool ?? true
      self?.sharingType = block ? .none : .readOnly
      result(nil)
    }

    // 選單列常駐：關掉視窗只是藏起來（見 MenuBarController）
    self.isReleasedWhenClosed = false
    self.delegate = self
    MenuBarController.shared.attach(window: self, messenger: flutterViewController.engine.binaryMessenger)
    AppUpdate.shared.attach(messenger: flutterViewController.engine.binaryMessenger)

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }

  // 紅色按鈕與 ⌘W：打開選單列時只藏起視窗，App 繼續留在選單列
  func windowShouldClose(_ sender: NSWindow) -> Bool {
    guard MenuBarController.shared.isEnabled else { return true }
    MenuBarController.shared.hideMainWindow()
    return false
  }
}
