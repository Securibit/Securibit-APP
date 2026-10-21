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

    // 預設不允許截圖：視窗不出現在截圖、錄影與螢幕分享中；設定頁的「允許截圖」會再調整
    self.sharingType = .none
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
