import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
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

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
