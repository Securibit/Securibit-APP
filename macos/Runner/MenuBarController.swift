import Cocoa
import FlutterMacOS
import ServiceManagement

/*
 * 選單列常駐（channel：securibit/menubar，Dart 端見 lib/features/menubar/）：
 * - 選單列圖示（template 圖，跟著淺色／深色選單列變色），點開是原生 NSMenu，依群組列出驗證碼，點一下複製
 * - Dart 是唯一的資料來源：選單關著時 Dart 只送結構；打開時與開著的每一秒向 Dart 要最新內容
 *   （計時器加在 .common 模式，選單追蹤滑鼠時也會跑；選單關著時不跑）
 * - 原生端只拿到顯示用的文字，金鑰一直在 Dart；複製也是請 Dart 算當下的碼
 * - 打開選單列時，關掉主視窗只是藏起來並收起 Dock 圖示（.accessory），⌘Q 或「結束 Securibit」才真的結束
 * - 登入時自動開啟：macOS 13 以上用 SMAppService.mainApp
 */
final class MenuBarController: NSObject, NSMenuDelegate {
  static let shared = MenuBarController()

  // 打開選單列：關視窗只藏起來、不結束 App
  private(set) var isEnabled = false

  private weak var window: NSWindow?
  private var channel: FlutterMethodChannel?
  private var statusItem: NSStatusItem?
  private let menu = NSMenu()
  // 目前畫出來的內容與它的結構（結構沒變就只更新文字）
  private var model: [String: Any] = [:]
  private var structure = ""
  private var codeItems: [String: NSMenuItem] = [:]
  private var timer: Timer?
  private var isMenuOpen = false
  // 主視窗是不是被藏起來了
  private var windowHidden = false
  private var copiedReset: DispatchWorkItem?
  // 上方「顯示方式」選單的「顯示／隱藏側邊欄」：狀態由 Dart 告訴（setSidebar），點了請 Dart 切換
  private var sidebarItem: NSMenuItem?
  private var sidebarAvailable = false
  private var sidebarCollapsed = false

  func attach(window: NSWindow, messenger: FlutterBinaryMessenger) {
    self.window = window
    menu.delegate = self
    menu.autoenablesItems = false
    let channel = FlutterMethodChannel(name: "securibit/menubar", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
    self.channel = channel
    // MainMenu.xib 的選單是英文範本，App 啟動完成後換成自己的中文選單
    NotificationCenter.default.addObserver(
      forName: NSApplication.didFinishLaunchingNotification, object: nil, queue: .main
    ) { [weak self] _ in
      self?.installMainMenu()
    }
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any]
    switch call.method {
    case "setEnabled":
      setEnabled(args?["enabled"] as? Bool ?? false)
      result(nil)
    case "update":
      apply(args ?? [:])
      result(nil)
    case "launchAtLoginStatus":
      result(launchAtLoginStatus())
    case "setLaunchAtLogin":
      setLaunchAtLogin(args?["enabled"] as? Bool ?? false, result: result)
    case "showWindow":
      showMainWindow()
      result(nil)
    case "setSidebar":
      sidebarAvailable = args?["available"] as? Bool ?? false
      sidebarCollapsed = args?["collapsed"] as? Bool ?? false
      updateSidebarItem()
      result(nil)
    case "openLoginItemsSettings":
      if #available(macOS 13.0, *) { SMAppService.openSystemSettingsLoginItems() }
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - 選單列圖示

  private func setEnabled(_ enabled: Bool) {
    guard enabled != isEnabled else { return }
    isEnabled = enabled
    if enabled {
      let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
      if let button = item.button {
        let image = NSImage(named: "StatusIcon")
        image?.isTemplate = true
        button.image = image
        button.imagePosition = .imageLeft
        button.toolTip = "Securibit"
        button.setAccessibilityLabel("Securibit")
      }
      item.menu = menu
      statusItem = item
      rebuild()
    } else {
      stopTimer()
      if let item = statusItem { NSStatusBar.system.removeStatusItem(item) }
      statusItem = nil
      // 沒有選單列就不能藏著，叫回主視窗
      if windowHidden { showMainWindow() }
    }
  }

  // MARK: - 選單內容

  private func apply(_ next: [String: Any]) {
    model = next
    let key = structureKey(next)
    if key != structure {
      rebuild()
      return
    }
    updateItems()
  }

  // 狀態、訊息、群組、各筆 id 與說明都一樣時視為同一個結構
  private func structureKey(_ model: [String: Any]) -> String {
    var parts = [
      model["status"] as? String ?? "",
      model["message"] as? String ?? "",
      "\(model["submenus"] as? Bool ?? false)",
      "\(model["showSettings"] as? Bool ?? false)",
    ]
    for section in sections(model) {
      parts.append("#\(section["id"] as? String ?? "")|\(section["title"] as? String ?? "")|\(section["note"] as? String ?? "")")
      for item in items(section) { parts.append(item["id"] as? String ?? "") }
    }
    return parts.joined(separator: "\n")
  }

  private func sections(_ model: [String: Any]) -> [[String: Any]] {
    model["sections"] as? [[String: Any]] ?? []
  }

  private func items(_ section: [String: Any]) -> [[String: Any]] {
    section["items"] as? [[String: Any]] ?? []
  }

  private func rebuild() {
    structure = structureKey(model)
    menu.removeAllItems()
    codeItems = [:]
    let status = model["status"] as? String ?? "loading"

    if let message = model["message"] as? String {
      // 已鎖定時點一下打開 App 解鎖
      let locked = status == "locked"
      let item = NSMenuItem(title: message, action: locked ? #selector(openApp) : nil, keyEquivalent: "")
      item.target = self
      item.isEnabled = locked
      menu.addItem(item)
    }

    let groups = sections(model)
    if model["submenus"] as? Bool ?? false {
      // 驗證碼很多時每個群組收成一個子選單
      for section in groups {
        let parent = NSMenuItem(title: section["title"] as? String ?? "", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        addSectionContent(section, to: submenu)
        parent.submenu = submenu
        menu.addItem(parent)
      }
    } else {
      for (index, section) in groups.enumerated() {
        if index > 0 { menu.addItem(.separator()) }
        menu.addItem(sectionHeader(section["title"] as? String ?? ""))
        addSectionContent(section, to: menu)
      }
    }

    if menu.numberOfItems > 0 { menu.addItem(.separator()) }
    let open = NSMenuItem(title: "打開 Securibit", action: #selector(openApp), keyEquivalent: "")
    open.target = self
    menu.addItem(open)
    if model["showSettings"] as? Bool ?? false {
      let settings = NSMenuItem(title: "設定…", action: #selector(openSettings), keyEquivalent: ",")
      settings.target = self
      menu.addItem(settings)
    }
    menu.addItem(.separator())
    let quit = NSMenuItem(title: "結束 Securibit", action: #selector(quit), keyEquivalent: "q")
    quit.target = self
    menu.addItem(quit)

    updateItems()
  }

  private func addSectionContent(_ section: [String: Any], to target: NSMenu) {
    let list = items(section)
    if list.isEmpty {
      let note = NSMenuItem(title: section["note"] as? String ?? "", action: nil, keyEquivalent: "")
      note.isEnabled = false
      target.addItem(note)
      return
    }
    for entry in list {
      guard let id = entry["id"] as? String else { continue }
      let item = NSMenuItem(title: entry["name"] as? String ?? "", action: #selector(copyCode(_:)), keyEquivalent: "")
      item.target = self
      item.representedObject = id
      target.addItem(item)
      codeItems[id] = item
    }
  }

  private func sectionHeader(_ title: String) -> NSMenuItem {
    if #available(macOS 14.0, *) {
      return NSMenuItem.sectionHeader(title: title)
    }
    let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
    item.attributedTitle = NSAttributedString(
      string: title,
      attributes: [.font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold)]
    )
    item.isEnabled = false
    return item
  }

  // 名稱靠左；驗證碼（等寬數字）與剩餘秒數用靠右的定位點對齊成兩欄
  private func updateItems() {
    let nameFont = NSFont.menuFont(ofSize: 0)
    let codeFont = NSFont.monospacedDigitSystemFont(ofSize: nameFont.pointSize, weight: .semibold)
    let secondsFont = NSFont.monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
    let entries = sections(model).flatMap { items($0) }

    func width(_ text: String, _ font: NSFont) -> CGFloat {
      ceil(NSAttributedString(string: text, attributes: [.font: font]).size().width)
    }
    let nameWidth = entries.map { width($0["name"] as? String ?? "", nameFont) }.max() ?? 0
    let codeWidth = entries.map { width($0["code"] as? String ?? "", codeFont) }.max() ?? 0
    let secondsWidth = entries.map { width($0["remaining"] as? String ?? "", secondsFont) }.max() ?? 0
    let codeStop = nameWidth + 28 + codeWidth
    let secondsStop = codeStop + 10 + secondsWidth
    let paragraph = NSMutableParagraphStyle()
    paragraph.tabStops = [
      NSTextTab(textAlignment: .right, location: codeStop),
      NSTextTab(textAlignment: .right, location: secondsStop),
    ]

    for entry in entries {
      guard let id = entry["id"] as? String, let item = codeItems[id] else { continue }
      let title = NSMutableAttributedString(
        string: entry["name"] as? String ?? "",
        attributes: [.font: nameFont, .paragraphStyle: paragraph]
      )
      // 快到期時變紅（同 App）
      var codeAttributes: [NSAttributedString.Key: Any] = [.font: codeFont, .paragraphStyle: paragraph]
      if entry["expiring"] as? Bool ?? false { codeAttributes[.foregroundColor] = NSColor.systemRed }
      title.append(NSAttributedString(string: "\t" + (entry["code"] as? String ?? ""), attributes: codeAttributes))
      if let remaining = entry["remaining"] as? String {
        title.append(NSAttributedString(
          string: "\t" + remaining,
          attributes: [.font: secondsFont, .foregroundColor: NSColor.secondaryLabelColor, .paragraphStyle: paragraph]
        ))
      }
      item.attributedTitle = title
      item.isEnabled = entry["copyable"] as? Bool ?? false
    }
  }

  // MARK: - NSMenuDelegate

  func menuWillOpen(_ menu: NSMenu) {
    guard menu === self.menu else { return }
    isMenuOpen = true
    requestSnapshot("menuWillOpen")
    startTimer()
  }

  func menuDidClose(_ menu: NSMenu) {
    guard menu === self.menu else { return }
    isMenuOpen = false
    stopTimer()
    channel?.invokeMethod("menuDidClose", arguments: nil)
  }

  private func requestSnapshot(_ method: String) {
    channel?.invokeMethod(method, arguments: nil) { [weak self] result in
      guard let self, self.isMenuOpen, let next = result as? [String: Any] else { return }
      self.apply(next)
    }
  }

  // 對齊整秒，每秒向 Dart 要一次最新的驗證碼；加在 .common 模式，選單開著（event tracking）時才會跑
  private func startTimer() {
    stopTimer()
    let now = Date().timeIntervalSince1970
    let firstFire = Date(timeIntervalSince1970: floor(now) + 1.005)
    let timer = Timer(fire: firstFire, interval: 1, repeats: true) { [weak self] _ in
      self?.requestSnapshot("tick")
    }
    timer.tolerance = 0.05
    RunLoop.main.add(timer, forMode: .common)
    self.timer = timer
  }

  private func stopTimer() {
    timer?.invalidate()
    timer = nil
  }

  // MARK: - 動作

  @objc private func copyCode(_ sender: NSMenuItem) {
    guard let id = sender.representedObject as? String else { return }
    channel?.invokeMethod("copy", arguments: ["id": id]) { [weak self] result in
      if result as? Bool == true { self?.showCopied() }
    }
  }

  // 複製後圖示旁短暫顯示「已複製」
  private func showCopied() {
    guard let button = statusItem?.button else { return }
    copiedReset?.cancel()
    button.title = "已複製"
    let reset = DispatchWorkItem { [weak self] in self?.statusItem?.button?.title = "" }
    copiedReset = reset
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: reset)
  }

  @objc private func openApp() {
    showMainWindow()
  }

  @objc private func openSettings() {
    showMainWindow()
    channel?.invokeMethod("openSettings", arguments: nil)
  }

  @objc private func quit() {
    NSApp.terminate(nil)
  }

  // MARK: - 主視窗

  /// 叫回主視窗並切到前景；Dock 圖示也跟著回來
  func showMainWindow() {
    guard let window else { return }
    if NSApp.activationPolicy() != .regular { NSApp.setActivationPolicy(.regular) }
    if window.isMiniaturized { window.deminiaturize(nil) }
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    if windowHidden {
      windowHidden = false
      channel?.invokeMethod("windowDidShow", arguments: nil)
    }
  }

  /// 關掉主視窗時改成藏起來，並收起 Dock 圖示。先讓 Dart 鎖定並畫好畫面再藏，最多等 0.5 秒
  func hideMainWindow() {
    guard let window, !windowHidden else { return }
    windowHidden = true
    var done = false
    let finish = { [weak self] in
      guard let self, !done else { return }
      done = true
      // 這段時間內又被叫回來就不藏了
      guard self.windowHidden else { return }
      window.orderOut(nil)
      if self.isEnabled { NSApp.setActivationPolicy(.accessory) }
    }
    channel?.invokeMethod("windowWillHide", arguments: nil) { _ in finish() }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: finish)
  }

  // MARK: - 登入時自動開啟

  private func launchAtLoginStatus() -> String {
    guard #available(macOS 13.0, *) else { return "unsupported" }
    switch SMAppService.mainApp.status {
    case .enabled: return "enabled"
    case .requiresApproval: return "requiresApproval"
    default: return "disabled"
    }
  }

  private func setLaunchAtLogin(_ enabled: Bool, result: @escaping FlutterResult) {
    guard #available(macOS 13.0, *) else {
      result("unsupported")
      return
    }
    let service = SMAppService.mainApp
    do {
      if enabled {
        try service.register()
      } else if service.status == .enabled || service.status == .requiresApproval {
        // 沒登記過時 unregister 會丟錯，不用取消
        try service.unregister()
      }
      result(launchAtLoginStatus())
    } catch {
      result(FlutterError(code: "launch-at-login", message: error.localizedDescription, details: nil))
    }
  }
}

// MARK: - 上方的 App 選單

extension MenuBarController {
  private static let repoURL = "https://github.com/Securibit/Securibit-APP"

  /// Securibit（關於、檢查更新、設定、服務、隱藏、結束）、編輯、顯示方式（側邊欄、全螢幕）、視窗、說明
  func installMainMenu() {
    let main = NSMenu()

    let app = NSMenu(title: "Securibit")
    app.addItem(menuItem("關於 Securibit", #selector(showAbout)))
    app.addItem(menuItem("檢查更新…", #selector(checkForUpdates)))
    app.addItem(.separator())
    app.addItem(menuItem("設定…", #selector(openSettings), key: ","))
    app.addItem(.separator())
    let services = NSMenu(title: "服務")
    app.addItem(submenuItem("服務", services))
    NSApp.servicesMenu = services
    app.addItem(.separator())
    app.addItem(standardItem("隱藏 Securibit", #selector(NSApplication.hide(_:)), key: "h"))
    let hideOthers = standardItem("隱藏其他", #selector(NSApplication.hideOtherApplications(_:)), key: "h")
    hideOthers.keyEquivalentModifierMask = [.command, .option]
    app.addItem(hideOthers)
    app.addItem(standardItem("顯示全部", #selector(NSApplication.unhideAllApplications(_:))))
    app.addItem(.separator())
    app.addItem(standardItem("結束 Securibit", #selector(NSApplication.terminate(_:)), key: "q"))
    main.addItem(submenuItem("Securibit", app))

    // 文字欄位的剪貼簿操作走 responder chain（同原本 xib 的 First Responder）
    let edit = NSMenu(title: "編輯")
    edit.addItem(standardItem("還原", Selector(("undo:")), key: "z"))
    edit.addItem(standardItem("重做", Selector(("redo:")), key: "Z"))
    edit.addItem(.separator())
    edit.addItem(standardItem("剪下", #selector(NSText.cut(_:)), key: "x"))
    edit.addItem(standardItem("拷貝", #selector(NSText.copy(_:)), key: "c"))
    edit.addItem(standardItem("貼上", #selector(NSText.paste(_:)), key: "v"))
    edit.addItem(standardItem("刪除", #selector(NSText.delete(_:))))
    edit.addItem(standardItem("全選", #selector(NSText.selectAll(_:)), key: "a"))
    main.addItem(submenuItem("編輯", edit))

    let view = NSMenu(title: "顯示方式")
    // ⌃⌘S 同系統的「顯示／隱藏側邊欄」；Flutter 先收到按鍵，Dart 處理了就不會再觸發這裡
    let sidebar = menuItem("隱藏側邊欄", #selector(toggleSidebar), key: "s")
    sidebar.keyEquivalentModifierMask = [.command, .control]
    view.addItem(sidebar)
    sidebarItem = sidebar
    updateSidebarItem()
    view.addItem(.separator())
    let fullScreen = standardItem("進入全螢幕", #selector(NSWindow.toggleFullScreen(_:)), key: "f")
    fullScreen.keyEquivalentModifierMask = [.command, .control]
    view.addItem(fullScreen)
    main.addItem(submenuItem("顯示方式", view))

    let window = NSMenu(title: "視窗")
    window.addItem(standardItem("縮到最小", #selector(NSWindow.performMiniaturize(_:)), key: "m"))
    window.addItem(standardItem("縮放", #selector(NSWindow.performZoom(_:))))
    window.addItem(standardItem("關閉視窗", #selector(NSWindow.performClose(_:)), key: "w"))
    window.addItem(.separator())
    window.addItem(standardItem("將此 App 的所有視窗移至最前", #selector(NSApplication.arrangeInFront(_:))))
    main.addItem(submenuItem("視窗", window))
    NSApp.windowsMenu = window

    let help = NSMenu(title: "說明")
    help.addItem(menuItem("GitHub 開源專案", #selector(openRepo)))
    help.addItem(menuItem("回報問題", #selector(openIssues)))
    main.addItem(submenuItem("說明", help))
    NSApp.helpMenu = help

    NSApp.mainMenu = main
  }

  private func menuItem(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
    let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
    item.target = self
    return item
  }

  // 沒有 target：送給目前的 first responder（文字欄位、視窗、NSApp）
  private func standardItem(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
    NSMenuItem(title: title, action: action, keyEquivalent: key)
  }

  private func submenuItem(_ title: String, _ submenu: NSMenu) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
    item.submenu = submenu
    return item
  }

  @objc private func showAbout() {
    let credits = NSMutableAttributedString(
      string: "由幣友 BITYO 與靈魂之神工作室共同開發\n開發者：夏特稀、糖豆魚\n",
      attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor]
    )
    credits.append(NSAttributedString(
      string: "GitHub 開源專案",
      attributes: [.font: NSFont.systemFont(ofSize: 11), .link: URL(string: Self.repoURL)!]
    ))
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    paragraph.lineSpacing = 2
    credits.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: credits.length))
    NSApp.activate(ignoringOtherApps: true)
    NSApp.orderFrontStandardAboutPanel(options: [.applicationName: "Securibit", .credits: credits])
  }

  private func updateSidebarItem() {
    sidebarItem?.title = sidebarCollapsed ? "顯示側邊欄" : "隱藏側邊欄"
  }

  @objc private func toggleSidebar() {
    channel?.invokeMethod("toggleSidebar", arguments: nil)
  }

  @objc private func checkForUpdates() {
    showMainWindow()
    channel?.invokeMethod("checkForUpdates", arguments: nil)
  }

  @objc private func openRepo() {
    NSWorkspace.shared.open(URL(string: Self.repoURL)!)
  }

  @objc private func openIssues() {
    NSWorkspace.shared.open(URL(string: Self.repoURL + "/issues")!)
  }
}

// MARK: - 上方選單的項目能不能按

extension MenuBarController: NSMenuItemValidation {
  // 只有上方選單會問（選單列圖示的選單關掉了 autoenablesItems）；沒有可以收起來的側欄時變灰
  func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
    if menuItem.action == #selector(toggleSidebar) { return sidebarAvailable }
    return true
  }
}
