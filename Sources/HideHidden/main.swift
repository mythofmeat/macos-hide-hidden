import AppKit

private let app = NSApplication.shared

// One copy at a time: brew services and the "Launch at login" item can both start it, and two copies
// would turn every tap into two middle clicks.
if NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
  .contains(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
  exit(0)
}

let accessibilityMonitor = AccessibilityMonitor()

// Middle click (vendored MiddleClick)
let controller = Controller()
controller.start()

// Cmd+Tab replacement that skips hidden apps
let switcher = Switcher()
switcher.start()

let trayMenu = TrayMenu()

accessibilityMonitor.start()

app.delegate = trayMenu

app.run()
