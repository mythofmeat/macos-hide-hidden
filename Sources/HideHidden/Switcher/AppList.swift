import AppKit

/// Running apps in most-recently-activated order, plus pre-rendered icons.
///
/// Everything here is kept current from NSWorkspace notifications so that summoning the switcher
/// never has to query the system or decode an icon. That's the whole speed trick.
@MainActor final class AppList: NSObject {
  /// Front-most first. Includes every running app; filtering happens in `switchable()`.
  private(set) var mru: [NSRunningApplication] = []

  /// Icons are rendered once per app at this size (in pixels) and scaled down by Core Animation if needed.
  var iconPixelSize = 0 {
    didSet { if oldValue != iconPixelSize { icons.removeAll() } }
  }
  private var icons: [pid_t: CGImage] = [:]

  override init() {
    super.init()
    seed()
    observe()
  }

  /// What the switcher shows: apps with a Dock icon and a window on the current desktop, front-most first.
  /// That leaves out hidden apps, apps with no windows (Finder included), apps whose windows are all
  /// minimized or on other desktops, and fullscreen apps (each has a desktop of its own).
  func switchable() -> [NSRunningApplication] {
    if let front = NSWorkspace.shared.frontmostApplication { moveToFront(front) }
    let onDesktop = Self.appsWithWindowsOnCurrentDesktop()
    return mru.filter {
      $0.activationPolicy == .regular && !$0.isHidden && !$0.isTerminated
        && onDesktop.contains($0.processIdentifier)
    }
  }

  /// "On screen" means on the current desktop and not minimized. One window server round trip,
  /// about 0.4 ms (the first call per process is ~50 ms, which `seed()` pays at launch).
  private static func appsWithWindowsOnCurrentDesktop() -> Set<pid_t> {
    let windows = CGWindowListCopyWindowInfo(
      [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
    ) as? [[String: Any]] ?? []
    var pids = Set<pid_t>()
    for window in windows {
      // Normal windows only, skipping the invisible and tiny helper windows some apps keep around.
      guard (window[kCGWindowLayer as String] as? Int) == 0,
            (window[kCGWindowAlpha as String] as? Double ?? 1) > 0,
            let bounds = window[kCGWindowBounds as String] as? [String: Double],
            bounds["Width", default: 0] >= 50, bounds["Height", default: 0] >= 50,
            let pid = window[kCGWindowOwnerPID as String] as? pid_t
      else { continue }
      pids.insert(pid)
    }
    return pids
  }

  func moveToFront(_ app: NSRunningApplication) {
    let pid = app.processIdentifier
    if mru.first?.processIdentifier == pid { return }
    mru.removeAll { $0.processIdentifier == pid }
    mru.insert(app, at: 0)
  }

  func icon(for app: NSRunningApplication) -> CGImage? {
    let pid = app.processIdentifier
    if let cached = icons[pid] { return cached }
    guard iconPixelSize > 0, let image = app.icon, let rendered = Self.render(image, pixels: iconPixelSize) else {
      return nil
    }
    icons[pid] = rendered
    return rendered
  }

  /// Render icons for every switchable app ahead of time.
  func prewarmIcons() {
    for app in mru where app.activationPolicy == .regular {
      _ = icon(for: app)
    }
  }

  private static func render(_ image: NSImage, pixels: Int) -> CGImage? {
    guard let ctx = CGContext(
      data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
      space: CGColorSpace(name: CGColorSpace.sRGB)!,
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
    image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
    NSGraphicsContext.restoreGraphicsState()
    return ctx.makeImage()
  }

  /// Best-effort initial order: front app, then owners of on-screen windows front-to-back, then the rest.
  private func seed() {
    let running = NSWorkspace.shared.runningApplications
    var byPid: [pid_t: NSRunningApplication] = [:]
    for app in running { byPid[app.processIdentifier] = app }

    var ordered: [NSRunningApplication] = []
    var seen = Set<pid_t>()
    func add(_ pid: pid_t) {
      guard !seen.contains(pid), let app = byPid[pid] else { return }
      seen.insert(pid)
      ordered.append(app)
    }

    if let front = NSWorkspace.shared.frontmostApplication { add(front.processIdentifier) }
    let windows = CGWindowListCopyWindowInfo(
      [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
    ) as? [[String: Any]] ?? []
    for window in windows where (window[kCGWindowLayer as String] as? Int) == 0 {
      if let pid = window[kCGWindowOwnerPID as String] as? pid_t { add(pid) }
    }
    for app in running { add(app.processIdentifier) }

    mru = ordered
  }

  private func observe() {
    let center = NSWorkspace.shared.notificationCenter
    center.addObserver(
      self, selector: #selector(didActivate), name: NSWorkspace.didActivateApplicationNotification, object: nil)
    center.addObserver(
      self, selector: #selector(didLaunch), name: NSWorkspace.didLaunchApplicationNotification, object: nil)
    center.addObserver(
      self, selector: #selector(didTerminate), name: NSWorkspace.didTerminateApplicationNotification, object: nil)
  }

  @objc private func didActivate(_ note: Notification) {
    guard let app = Self.app(from: note) else { return }
    moveToFront(app)
  }

  @objc private func didLaunch(_ note: Notification) {
    guard let app = Self.app(from: note) else { return }
    let pid = app.processIdentifier
    if !mru.contains(where: { $0.processIdentifier == pid }) {
      // Launched in the background: goes after the front app, like the native switcher.
      mru.insert(app, at: min(1, mru.count))
    }
    _ = icon(for: app)
  }

  @objc private func didTerminate(_ note: Notification) {
    guard let app = Self.app(from: note) else { return }
    let pid = app.processIdentifier
    mru.removeAll { $0.processIdentifier == pid }
    icons[pid] = nil
  }

  private static func app(from note: Notification) -> NSRunningApplication? {
    note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
  }
}
