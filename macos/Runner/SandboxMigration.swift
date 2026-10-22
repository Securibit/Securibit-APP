import Foundation

/*
 * 1.2.0 起關掉 App Sandbox（為了能自動更新：替換自己的 .app），App 的資料位置跟著改變：
 *   沙盒：~/Library/Containers/com.bityo.securibit/Data/Library/…
 *   現在：~/Library/…
 * 第一次以非沙盒啟動時，把舊 container 裡用得到的資料搬過來（只搬一次，舊資料不刪，萬一要退回舊版還在）：
 * - Preferences/com.bityo.securibit.plist（SharedPreferences 存在 NSUserDefaults：主題、選單列、登入時開啟、
 *   上次選的群組、自動檢查更新、Google 登入的狀態、視窗位置…）：新位置沒有的 key 才搬，不蓋掉已經有的
 * - Application Support/com.bityo.securibit（path_provider 的 getApplicationSupportDirectory）：新位置還沒有才整個複製
 * 不用搬的：
 * - 登入 session、App 鎖定、離線快取、裝置金鑰都在鑰匙圈（flutter_secure_storage，用傳統的登入鑰匙圈、沒有 access group），
 *   沙盒與非沙盒讀的是同一個項目；存取權限看 App 的簽章（同一張憑證簽的就能讀），和沙盒無關
 * - Caches（Flutter 引擎的快取，會自己重建）、Documents（App 沒有用）、tmp
 * 一定要在 Flutter 引擎啟動前執行（MainFlutterWindow.awakeFromNib 的第一行），Dart 讀設定時才讀得到搬過來的值。
 */
enum SandboxMigration {
  static let doneKey = "securibit.sandboxMigrated"

  /// 搬過的項目（給測試與記錄用）
  struct Result: Equatable {
    var preferenceKeys: [String] = []
    var applicationSupport = false
  }

  static func runIfNeeded() {
    // 還在沙盒裡（例如舊的建置）就不用搬
    guard ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] == nil,
          let bundleID = Bundle.main.bundleIdentifier else { return }
    let defaults = UserDefaults.standard
    guard !defaults.bool(forKey: doneKey) else { return }
    let result = migrate(
      container: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Containers/\(bundleID)/Data"),
      home: FileManager.default.homeDirectoryForCurrentUser,
      bundleID: bundleID,
      defaults: defaults
    )
    defaults.set(true, forKey: doneKey)
    if !result.preferenceKeys.isEmpty || result.applicationSupport {
      NSLog("Securibit：從沙盒搬過來 %d 個設定%@", result.preferenceKeys.count, result.applicationSupport ? "與 Application Support" : "")
    }
  }

  /// container 是舊的沙盒資料夾（…/Containers/<id>/Data），home 是使用者的家目錄；defaults 的 domain 是 bundleID
  static func migrate(container: URL, home: URL, bundleID: String, defaults: UserDefaults, fileManager: FileManager = .default) -> Result {
    var result = Result()

    // 設定：讀舊的 plist（舊版已經結束，cfprefsd 早就寫回檔案了），新位置沒有的 key 才加
    let plist = container.appendingPathComponent("Library/Preferences/\(bundleID).plist")
    if let old = NSDictionary(contentsOf: plist) as? [String: Any], !old.isEmpty {
      var current = defaults.persistentDomain(forName: bundleID) ?? [:]
      for (key, value) in old where current[key] == nil && key != doneKey {
        current[key] = value
        result.preferenceKeys.append(key)
      }
      if !result.preferenceKeys.isEmpty {
        defaults.setPersistentDomain(current, forName: bundleID)
        result.preferenceKeys.sort()
      }
    }

    // Application Support/<bundleID>：新位置還沒有才複製（不合併，避免蓋掉新版已經寫的檔案）
    let oldSupport = container.appendingPathComponent("Library/Application Support/\(bundleID)")
    let newSupport = home.appendingPathComponent("Library/Application Support/\(bundleID)")
    var isDir: ObjCBool = false
    if fileManager.fileExists(atPath: oldSupport.path, isDirectory: &isDir), isDir.boolValue,
       !fileManager.fileExists(atPath: newSupport.path) {
      do {
        try fileManager.createDirectory(at: newSupport.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileManager.copyItem(at: oldSupport, to: newSupport)
        result.applicationSupport = true
      } catch {
        NSLog("Securibit：無法搬移 Application Support：%@", error.localizedDescription)
      }
    }
    return result
  }
}
