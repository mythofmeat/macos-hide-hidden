import AppKit
import ConfigCore

final class SwitcherConfig: ConfigCore {
  required init() {
    Self.options.cacheAll = true
  }

  @UserDefault var switcherEnabled = true
}

/// App-level Cmd+Tab replacement that leaves out hidden apps.
@MainActor final class Switcher {
  private let config = SwitcherConfig.shared
  private let appList = AppList()
  private lazy var panel = SwitcherPanel(appList: appList)
  private lazy var keyTap = SwitcherKeyTap(switcher: self)

  private var apps: [NSRunningApplication] = []
  private var selected = 0
  private(set) var isActive = false
  private var activationGeneration = 0
  private var isTrusted = false

  func start() {
    _ = panel
    accessibilityMonitor.addListener { [weak self] becameTrusted in
      self?.isTrusted = becameTrusted
      self?.updateTap()
    }
    config.$switcherEnabled.onSet { [weak self] _ in
      DispatchQueue.main.async { self?.updateTap() }
    }
  }

  private func updateTap() {
    if isTrusted && config.switcherEnabled {
      keyTap.start()
    } else {
      if isActive { cancel() }
      keyTap.stop()
    }
  }

  // MARK: Called by SwitcherKeyTap

  /// Returns false to let the native switcher handle this Cmd+Tab instead.
  func begin(backward: Bool) -> Bool {
    apps = appList.switchable()
    guard !apps.isEmpty else { return false }

    let frontPid = NSWorkspace.shared.frontmostApplication?.processIdentifier
    let firstOther = apps[0].processIdentifier == frontPid ? 1 : 0
    selected = backward ? apps.count - 1 : min(firstOther, apps.count - 1)
    isActive = true
    panel.show(apps, selected: selected)
    return true
  }

  func step(_ delta: Int) {
    guard isActive, !apps.isEmpty else { return }
    selected = (selected + delta + apps.count) % apps.count
    panel.select(selected)
  }

  func commit() {
    guard isActive else { return }
    let target = apps[selected]
    finish()
    activate(target)
  }

  func cancel() {
    guard isActive else { return }
    finish()
  }

  private func finish() {
    isActive = false
    panel.hide()
    apps = []
  }

  // MARK: Activation

  private func activate(_ app: NSRunningApplication) {
    guard !app.isActive, !app.isTerminated else { return }
    // Update the order now so a fast follow-up Cmd+Tab sees it, before the activation notification lands.
    appList.moveToFront(app)
    activationGeneration &+= 1
    let generation = activationGeneration

    if !app.activate(options: .activateAllWindows) {
      Self.forceFront(app)
      return
    }

    // A background app asking to activate another app can be ignored by the system
    // (cooperative activation, macOS 14+). If that happened, push it to the front directly.
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
      guard let self, self.activationGeneration == generation, !app.isActive, !app.isTerminated else { return }
      log.info("Switcher: activate() didn't take for \(app.localizedName ?? "?"), forcing front process.")
      Self.forceFront(app)
    }
  }

  private static func forceFront(_ app: NSRunningApplication) {
    var psn = ProcessSerialNumber()
    guard _GetProcessForPID(app.processIdentifier, &psn) == noErr else { return }
    _SLPSSetFrontProcessWithOptions(&psn, 0, SLPSMode.allWindows | SLPSMode.userGenerated)
  }
}

// MARK: Private SkyLight API (same call AltTab and yabai use to front a process)

private enum SLPSMode {
  static let allWindows: UInt32 = 0x100
  static let userGenerated: UInt32 = 0x200
}

@_silgen_name("_SLPSSetFrontProcessWithOptions") @discardableResult
private func _SLPSSetFrontProcessWithOptions(
  _ psn: UnsafeMutablePointer<ProcessSerialNumber>, _ wid: CGWindowID, _ mode: UInt32
) -> CGError

/// Deprecated Carbon call that Swift refuses to import, but it's still exported and still works.
@_silgen_name("GetProcessForPID")
private func _GetProcessForPID(_ pid: pid_t, _ psn: UnsafeMutablePointer<ProcessSerialNumber>) -> OSStatus
