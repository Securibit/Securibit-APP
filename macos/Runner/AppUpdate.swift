import Cocoa
import FlutterMacOS

/*
 * 自動更新的原生端（channel：securibit/update，Dart 端見 lib/features/update/update_installer.dart）：
 * App 不能在執行中把自己的 .app 換掉，Dart 準備好替換腳本後交給這裡（arm），
 * App 結束時（applicationWillTerminate：⌘Q、選單的「結束 Securibit」、登出關機）用 /bin/sh 啟動它，
 * 腳本等這個程序結束後替換 .app。「重新啟動並更新」是 arm（裝完重新打開）之後 quit。
 * 腳本是獨立的程序，App 結束後繼續跑；強制結束或當掉時不會啟動，下次開 App 會再提示。
 */
final class AppUpdate {
  static let shared = AppUpdate()

  private var channel: FlutterMethodChannel?
  private var pending: (script: String, arguments: [String])?

  func attach(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "securibit/update", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
    self.channel = channel
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "arm":
      let args = call.arguments as? [String: Any]
      guard let script = args?["script"] as? String, let arguments = args?["arguments"] as? [String] else {
        result(FlutterError(code: "bad_args", message: "缺少 script 或 arguments", details: nil))
        return
      }
      pending = (script, arguments)
      result(nil)
    case "disarm":
      pending = nil
      result(nil)
    case "quit":
      result(nil)
      // 等回覆送出去再結束
      DispatchQueue.main.async { NSApp.terminate(nil) }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// AppDelegate.applicationWillTerminate 呼叫：有準備好的更新就啟動替換腳本
  func launchPendingInstall() {
    guard let pending else { return }
    self.pending = nil
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/sh")
    process.arguments = [pending.script] + pending.arguments
    process.standardInput = FileHandle.nullDevice
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    do {
      try process.run()
    } catch {
      NSLog("Securibit：無法啟動更新程式：%@", error.localizedDescription)
    }
  }
}
