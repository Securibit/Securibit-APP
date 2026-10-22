import Cocoa
import FlutterMacOS
import XCTest

@testable import securibit

class RunnerTests: XCTestCase {
  private var root: URL!
  private var defaults: UserDefaults!
  private let domain = "com.bityo.securibit.migration-test"

  override func setUpWithError() throws {
    root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defaults = UserDefaults(suiteName: domain)
    defaults.removePersistentDomain(forName: domain)
  }

  override func tearDownWithError() throws {
    defaults.removePersistentDomain(forName: domain)
    try? FileManager.default.removeItem(at: root)
  }

  // 1.1.x（沙盒）→ 1.2.0（非沙盒）：舊 container 的設定與 Application Support 搬過來，已經有的不蓋掉，舊資料不刪
  func testMigratesSandboxContainer() throws {
    let container = root.appendingPathComponent("Containers/\(domain)/Data")
    let home = root.appendingPathComponent("home")
    let prefs = container.appendingPathComponent("Library/Preferences")
    try FileManager.default.createDirectory(at: prefs, withIntermediateDirectories: true)
    let old: NSDictionary = ["flutter.securibit:theme": "dark", "flutter.securibit:launchAtLogin": true, "NSWindow Frame SecuribitMainWindow": "1 2 3 4"]
    XCTAssertTrue(old.write(to: prefs.appendingPathComponent("\(domain).plist"), atomically: true))
    let support = container.appendingPathComponent("Library/Application Support/\(domain)")
    try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
    try Data("cache".utf8).write(to: support.appendingPathComponent("a.json"))
    defaults.setPersistentDomain(["flutter.securibit:theme": "light"], forName: domain)

    let result = SandboxMigration.migrate(container: container, home: home, bundleID: domain, defaults: defaults)
    XCTAssertEqual(result.preferenceKeys, ["NSWindow Frame SecuribitMainWindow", "flutter.securibit:launchAtLogin"])
    XCTAssertTrue(result.applicationSupport)
    let migrated = defaults.persistentDomain(forName: domain)
    XCTAssertEqual(migrated?["flutter.securibit:theme"] as? String, "light")
    XCTAssertEqual(migrated?["flutter.securibit:launchAtLogin"] as? Bool, true)
    let copied = home.appendingPathComponent("Library/Application Support/\(domain)/a.json")
    XCTAssertEqual(try String(contentsOf: copied, encoding: .utf8), "cache")
    XCTAssertTrue(FileManager.default.fileExists(atPath: support.appendingPathComponent("a.json").path))

    // 再跑一次不會重複搬
    let again = SandboxMigration.migrate(container: container, home: home, bundleID: domain, defaults: defaults)
    XCTAssertEqual(again, SandboxMigration.Result())
  }

  // 沒有舊 container（新安裝）時什麼都不做
  func testNothingToMigrate() {
    let result = SandboxMigration.migrate(container: root.appendingPathComponent("none"), home: root, bundleID: domain, defaults: defaults)
    XCTAssertEqual(result, SandboxMigration.Result())
  }
}
