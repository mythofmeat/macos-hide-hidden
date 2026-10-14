// Modified for HideHidden on 2026-10-14, from MiddleClick's TrayMenu.swift: removed the successor/promo
// items and the pre-macOS 13 fallbacks, swapped the asset-catalog status icon for an SF Symbol, and added
// the Cmd+Tab switcher toggle.
import ServiceManagement
import AppKit

@MainActor final class TrayMenu: NSObject {
  private let config = Config.shared
  private let switcherConfig = SwitcherConfig.shared
  private var infoItem, tapToClickItem, accessibilityPermissionStatusItem, accessibilityPermissionActionItem, ignoredAppItem, launchAtLoginItem, switcherItem: NSMenuItem!
  private var fingerCountControl: FingerCountControl!
  private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
  var isStatusItemVisible: Bool {
    get { statusItem.isVisible }
    set { statusItem.isVisible = newValue }
  }

  override init() {
    super.init()

    if Self.shouldDelayInit {
      DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: self.initSequence)
    } else {
      self.initSequence()
    }
  }
  private func initSequence() {
    setupStatusItem()
    accessibilityMonitor.addListener(onChange: updateAccessibilityPermissionStatus)
    config.$minimumFingers.onSet {_ in
      DispatchQueue.main.async {
        self.updateTapToClickStatus()
      }
    }
  }

  #if DEBUG
  private static let shouldDelayInit = terminateExistingInstance(force: false)
  #else
  private static let shouldDelayInit = false
  #endif

  private func updateAccessibilityPermissionStatus(_ hasAccessibilityPermission: Bool) {
    statusItem.button?.appearsDisabled = !hasAccessibilityPermission
    accessibilityPermissionStatusItem.isHidden = hasAccessibilityPermission
    accessibilityPermissionActionItem.isHidden = hasAccessibilityPermission
  }

  private func updateTapToClickStatus() {
    let tapToClick = config.tapToClick
    let clickModeInfo = "Click" + (tapToClick ? " or Tap" : "")
    let fingersInfo = " with \(config.minimumFingers)\(config.allowMoreFingers ? "+" : "") Fingers"

    infoItem.title = clickModeInfo + fingersInfo
    tapToClickItem.state = tapToClick ? .on : .off
  }

  private func createMenu() -> NSMenu {
    let menu = NSMenu()
    menu.delegate = self

    createMenuAccessibilityPermissionItems(menu)

    menu.addItem(.sectionHeader(title: "Middle Click"))

    ignoredAppItem = menu
      .addItem(
        withTitle: "Ignore focused app",
        action: #selector(ignoreApp),
        target: self
      )
    menu.addSeparator()

    infoItem = menu.addItem(withTitle: "")

    tapToClickItem = menu.addItem(
      withTitle: "Tap to click", action: #selector(toggleTapToClick), target: self)

    let resetItem = menu.addItem(
      withTitle: "Reset to System Settings", action: #selector(resetTapToClick), target: self)
    resetItem.isAlternate = true
    resetItem.keyEquivalentModifierMask = .option

    let advancedItem = menu.addItem(withTitle: "Advanced")
    let advancedMenu = NSMenu()
    advancedItem.submenu = advancedMenu

    addFingerCountItem(advancedMenu)

    updateTapToClickStatus()

    menu.addSeparator()

    menu.addItem(.sectionHeader(title: "Cmd+Tab"))
    switcherItem = menu.addItem(
      withTitle: "Replace native switcher", action: #selector(toggleSwitcher), target: self)
    switcherItem.state = switcherConfig.switcherEnabled ? .on : .off

    menu.addSeparator()

    launchAtLoginItem = menu.addItem(
      withTitle: "Launch at login",
      action: #selector(toggleLoginItem),
      target: self
    )
    updateLaunchAtLoginItem()

    _ = menu.addItem(withTitle: "Version \(BundleInfo.version)")

    #if DEBUG
    _ = menu.addItem(
      withTitle: "Restart listeners",
      action: #selector(restartNow),
      target: self,
      keyEquivalent: "r"
    )
    #endif

    menu.addSeparator()

    _ = menu.addItem(
      withTitle: "Quit", action: #selector(actionQuit), target: self, keyEquivalent: "q")

    return menu
  }

  private func createMenuAccessibilityPermissionItems(_ menu: NSMenu) {
    accessibilityPermissionStatusItem = menu.addItem(
      withTitle: "Missing Accessibility permission")
    accessibilityPermissionActionItem = menu.addItem(
      withTitle: "Open Privacy Preferences", action: #selector(openAccessibilitySettings), target: self,
      keyEquivalent: ",")
    menu.addSeparator()
  }

  private func getAppName() -> String {
    return ProcessInfo.processInfo.processName
  }

  private func setupStatusItem() {
    statusItem.behavior = .removalAllowed
    statusItem.menu = createMenu()
    statusItem.button?.toolTip = getAppName()
    statusItem.button?.image = createStatusIcon()
  }

  private func createStatusIcon() -> NSImage {
    let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
    let icon = NSImage(systemSymbolName: "computermouse", accessibilityDescription: getAppName())!
      .withSymbolConfiguration(config)!
    icon.isTemplate = true
    return icon
  }

  #if DEBUG
  private var timesHandledReopen = 0
  var restartListeners: (() -> Void)?
  #endif
}

#if DEBUG
// MARK: Dev-only
extension TrayMenu {
  private static func terminateExistingInstance(force: Bool = true) -> Bool {
    let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier!).filter {
      $0.processIdentifier != ProcessInfo.processInfo.processIdentifier
    }

    for app in runningApps {
      log.info("Terminating existing instance of MiddleClick (PID: \(app.processIdentifier))")
      if force { return app.forceTerminate() } else { return app.terminate() }
    }

    return runningApps.count > 0
  }
}
#endif

// MARK: Actions
extension TrayMenu {
  @objc private func openAccessibilitySettings() {
    if let url = URL(
      string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
      NSWorkspace.shared.open(url)
    }
  }

  @objc private func toggleSwitcher() {
    switcherConfig.switcherEnabled.toggle()
    switcherItem.state = switcherConfig.switcherEnabled ? .on : .off
  }

  @objc private func toggleTapToClick(sender: NSButton) {
    config.tapToClick = sender.state == .off
    updateTapToClickStatus()
  }

  @objc private func resetTapToClick() {
    config.$tapToClick.delete()
    updateTapToClickStatus()
  }

  @objc private func actionQuit(sender: Any) {
    NSApp.terminate(sender)
  }

  #if DEBUG
  @objc private func restartNow() {
    restartListeners?()
  }
  #endif
}

extension TrayMenu: NSApplicationDelegate {
  #if DEBUG
    private func isRunningInXcode() -> Bool {
      return ProcessInfo.processInfo.environment["IDE_DISABLED_OS_ACTIVITY_DT_MODE"] != nil
    }
  #endif

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
  #if DEBUG
      guard !isRunningInXcode() || timesHandledReopen >= 2 else {
        timesHandledReopen += 1
        return true
      }
  #endif

      statusItem.isVisible = true
      Timer.scheduledTimer(withTimeInterval: 0.01, repeats: false) { _ in
        DispatchQueue.main.async {
          self.statusItem.button?.performClick(nil)
        }
      }

      return true
    }
}

// Launch at login:
extension TrayMenu {
  @objc private func toggleLoginItem() {
    modifyLoginItem(add: launchAtLoginItem.state == .off)
    updateLaunchAtLoginItem()
  }
  private func updateLaunchAtLoginItem() {
    launchAtLoginItem.state = isLoginItemEnabled() ? .on : .off
  }
  private func isLoginItemEnabled() -> Bool {
    return SMAppService.mainApp.status == .enabled
  }
  private func modifyLoginItem(add: Bool) {
    do {
      if add {
        try SMAppService.mainApp.register()
      } else {
        try SMAppService.mainApp.unregister()
      }
    } catch {
      log.error("Failed to \(add ? "add" : "remove") to login items: \(error)")
    }
  }
}

extension TrayMenu {
  private func addFingerCountItem(_ menu: NSMenu) {
    fingerCountControl = FingerCountControl()
    fingerCountControl.onValueChanged = { _ in
      self.updateTapToClickStatus()
    }

    let fingerCountItem = NSMenuItem()
    fingerCountItem.view = fingerCountControl
    menu.addItem(fingerCountItem)

    let resetFingerCountItem = menu.addItem(
      withTitle: "Reset Finger Count", action: #selector(resetFingerCount), target: self)
    resetFingerCountItem.isAlternate = true
    resetFingerCountItem.keyEquivalentModifierMask = .option
  }

  @objc private func resetFingerCount() {
    config.$minimumFingers.delete()
    fingerCountControl.refresh()
  }
}

extension TrayMenu: NSMenuDelegate {
  func menuWillOpen(_ menu: NSMenu) {
    updateIgnoredAppItem()
    fingerCountControl.refresh()
  }

  private func updateIgnoredAppItem() {
    let focusedApp = AppUtils.getFocusedApp()
    if let focusedAppName = focusedApp?.localizedName {
      ignoredAppItem.title = "Ignore " + focusedAppName
      ignoredAppItem.state = AppUtils.isIgnoredAppBundle(focusedApp) ? .on : .off
    }
  }

  @objc private func ignoreApp() {
    guard let focusedBundleID = AppUtils.getFocusedApp()?.bundleIdentifier else { return }

    config.ignoredAppBundles.formSymmetricDifference([focusedBundleID])
  }
}

extension NSMenu {
  func addItem(withTitle string: String, action selector: Selector, target: AnyObject, keyEquivalent charCode: String = "") -> NSMenuItem {
    let menuItem = NSMenuItem(title: string, action: selector, keyEquivalent: charCode)
    menuItem.target = target
    self.addItem(menuItem)
    return menuItem
  }
  func addItem(withTitle string: String) -> NSMenuItem {
    return self.addItem(withTitle: string, action: nil, keyEquivalent: "")
  }

  func addSeparator() {
    self.addItem(.separator())
  }
}

class BundleInfo {
  private static func bundleInfo(_ key: String) -> String {
    return Bundle.main.infoDictionary?[key] as? String ?? "%\(key)%"
  }

  static let version = bundleInfo("CFBundleShortVersionString")
}
