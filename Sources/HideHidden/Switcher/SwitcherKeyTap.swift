import AppKit
import Carbon.HIToolbox

/// Intercepts Cmd+Tab at the HID level, before the Dock's native switcher sees it.
///
/// The native shortcut is deliberately left enabled: if this app quits, crashes, or loses its tap
/// (e.g. while Secure Input is on in a password field), the stock switcher just works instead.
@MainActor final class SwitcherKeyTap: PointerableObject {
  private unowned let switcher: Switcher
  private var tap: CFMachPort?
  private var source: CFRunLoopSource?
  /// Keys whose keyDown we swallowed; their keyUp must be swallowed too.
  private var swallowedKeyUps = Set<Int>()

  init(switcher: Switcher) {
    self.switcher = switcher
  }

  var isRunning: Bool { tap != nil }

  @discardableResult
  func start() -> Bool {
    if tap != nil { return true }
    let events: [CGEventType] = [.keyDown, .keyUp, .flagsChanged]
    let mask = events.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
    guard let tap = CGEvent.tapCreate(
      tap: .cghidEventTap,
      place: .headInsertEventTap,
      options: .defaultTap,
      eventsOfInterest: mask,
      callback: Self.callback,
      userInfo: rawPointer
    ) else {
      log.error("Switcher: failed to create keyboard tap (check Accessibility permission).")
      return false
    }
    let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
    CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    CGEvent.tapEnable(tap: tap, enable: true)
    self.tap = tap
    self.source = source
    log.info("Switcher: keyboard tap started.")
    return true
  }

  func stop() {
    guard let tap else { return }
    CGEvent.tapEnable(tap: tap, enable: false)
    if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
    CFMachPortInvalidate(tap)
    self.tap = nil
    self.source = nil
    swallowedKeyUps.removeAll()
    log.info("Switcher: keyboard tap stopped.")
  }

  private static let callback: CGEventTapCallBack = { _, type, event, userInfo in
    // The run loop source is on the main run loop, so we're already on the main thread.
    nonisolated(unsafe) let event = event
    nonisolated(unsafe) let userInfo = userInfo
    let swallow = MainActor.assumeIsolated {
      SwitcherKeyTap.from(pointer: userInfo).handle(type, event)
    }
    return swallow ? nil : Unmanaged.passUnretained(event)
  }

  /// Returns true to swallow the event.
  private func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
    switch type {
    case .tapDisabledByTimeout, .tapDisabledByUserInput:
      log.info("Switcher: tap was disabled (\(type.rawValue)), re-enabling.")
      if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
      return false

    case .keyDown:
      let key = Int(event.getIntegerValueField(.keyboardEventKeycode))
      let flags = event.flags

      guard switcher.isActive else {
        guard key == kVK_Tab,
              flags.contains(.maskCommand),
              flags.isDisjoint(with: [.maskControl, .maskAlternate]),
              switcher.begin(backward: flags.contains(.maskShift))
        else { return false }
        swallowedKeyUps = [key]
        return true
      }

      // Cmd went up without us seeing it (it happens): finish the switch and let this key through.
      guard flags.contains(.maskCommand) else {
        switcher.commit()
        return false
      }

      swallowedKeyUps.insert(key)
      switch key {
      case kVK_Tab: switcher.step(flags.contains(.maskShift) ? -1 : 1)
      case kVK_ANSI_Grave, kVK_LeftArrow: switcher.step(-1)
      case kVK_RightArrow: switcher.step(1)
      case kVK_Escape: switcher.cancel()
      default: break
      }
      // Swallow everything else while the switcher is up so it doesn't leak into the front app.
      return true

    case .keyUp:
      let key = Int(event.getIntegerValueField(.keyboardEventKeycode))
      return swallowedKeyUps.remove(key) != nil || switcher.isActive

    case .flagsChanged:
      if switcher.isActive && !event.flags.contains(.maskCommand) {
        switcher.commit()
      }
      return false

    default:
      return false
    }
  }
}
