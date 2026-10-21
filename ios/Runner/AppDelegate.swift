import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  /*
   * 截圖與多工畫面的保護（lib/features/settings/screen_privacy.dart）。
   * iOS 沒有公開的 API 能擋截圖，能做的是：
   * - 錄影、AirPlay 或鏡像輸出時（UIScreen.isCaptured）蓋上遮罩，錄到的只有遮罩
   * - 進多工畫面前（willResignActive）蓋上隱私畫面，App 切換器的縮圖看不到驗證碼
   * 預設兩者都開，Flutter 讀到設定後再調整。
   */
  private var blockCapture = true
  private var hideInSwitcher = true
  private var switcherCover: UIView?
  private var captureCover: UIView?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    if let registrar = registrar(forPlugin: "SecuribitPrivacy") {
      let channel = FlutterMethodChannel(name: "securibit/privacy", binaryMessenger: registrar.messenger())
      channel.setMethodCallHandler { [weak self] call, result in
        guard let self, call.method == "configure" else {
          result(FlutterMethodNotImplemented)
          return
        }
        let args = call.arguments as? [String: Any]
        self.blockCapture = args?["blockCapture"] as? Bool ?? true
        self.hideInSwitcher = args?["hideInSwitcher"] as? Bool ?? true
        self.updateCaptureCover()
        result(nil)
      }
    }
    let center = NotificationCenter.default
    center.addObserver(self, selector: #selector(willResignActive), name: UIApplication.willResignActiveNotification, object: nil)
    center.addObserver(self, selector: #selector(didBecomeActive), name: UIApplication.didBecomeActiveNotification, object: nil)
    center.addObserver(self, selector: #selector(updateCaptureCover), name: UIScreen.capturedDidChangeNotification, object: nil)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  @objc private func willResignActive() {
    guard hideInSwitcher, switcherCover == nil, let window else { return }
    let cover = makeCover(in: window, message: nil)
    switcherCover = cover
  }

  @objc private func didBecomeActive() {
    switcherCover?.removeFromSuperview()
    switcherCover = nil
    updateCaptureCover()
  }

  @objc private func updateCaptureCover() {
    guard let window else { return }
    let captured = window.screen.isCaptured
    if blockCapture && captured {
      if captureCover == nil {
        captureCover = makeCover(in: window, message: "錄影或鏡像輸出時不顯示內容")
      }
    } else {
      captureCover?.removeFromSuperview()
      captureCover = nil
    }
  }

  // 和 App 一樣的底色（淺色白、深色 #1C1C1E）加上標誌
  private func makeCover(in window: UIWindow, message: String?) -> UIView {
    let cover = UIView(frame: window.bounds)
    cover.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    cover.backgroundColor = UIColor { traits in
      traits.userInterfaceStyle == .dark ? UIColor(red: 0x1C / 255, green: 0x1C / 255, blue: 0x1E / 255, alpha: 1) : .white
    }

    let logo = UIImageView(image: UIImage(named: "LaunchImage"))
    logo.contentMode = .scaleAspectFit
    let stack = UIStackView(arrangedSubviews: [logo])
    stack.axis = .vertical
    stack.alignment = .center
    stack.spacing = 16
    if let message {
      let label = UILabel()
      label.text = message
      label.font = .systemFont(ofSize: 17, weight: .semibold)
      label.textColor = .secondaryLabel
      label.textAlignment = .center
      label.numberOfLines = 0
      stack.addArrangedSubview(label)
    }
    stack.translatesAutoresizingMaskIntoConstraints = false
    cover.addSubview(stack)
    NSLayoutConstraint.activate([
      logo.widthAnchor.constraint(equalToConstant: 72),
      logo.heightAnchor.constraint(equalToConstant: 72),
      stack.centerXAnchor.constraint(equalTo: cover.centerXAnchor),
      stack.centerYAnchor.constraint(equalTo: cover.centerYAnchor),
      stack.leadingAnchor.constraint(greaterThanOrEqualTo: cover.leadingAnchor, constant: 32),
    ])
    window.addSubview(cover)
    window.bringSubviewToFront(cover)
    return cover
  }
}
