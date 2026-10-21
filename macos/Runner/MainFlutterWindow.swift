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

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
