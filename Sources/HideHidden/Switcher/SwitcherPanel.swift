import AppKit

/// The on-screen switcher: a row of app icons with the selected one highlighted and named.
///
/// The window and views are built once. Showing it only repositions layers and orders the window in,
/// with every animation turned off.
@MainActor final class SwitcherPanel {
  private static let iconSize: CGFloat = 96
  private static let tilePadding: CGFloat = 10
  private static let edge: CGFloat = 16
  private static let labelHeight: CGFloat = 20
  private static let labelGap: CGFloat = 6
  private static let cornerRadius: CGFloat = 22
  private static let screenMargin: CGFloat = 40

  private let appList: AppList
  private let window: NSPanel
  private let effectView = NSVisualEffectView()
  private let tilesView = NSView()
  private let tilesLayer = CALayer()
  private let selectionLayer = CALayer()
  private var iconLayers: [CALayer] = []
  private let nameLabel = NSTextField(labelWithString: "")

  private var names: [String] = []
  private var tileSize: CGFloat = 0
  private var shownPids: [pid_t] = []
  private var shownScreenFrame: CGRect = .zero

  init(appList: AppList) {
    self.appList = appList

    window = NonActivatingPanel(
      contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    window.isFloatingPanel = true
    window.level = .popUpMenu
    window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
    window.backgroundColor = .clear
    window.isOpaque = false
    window.hasShadow = true
    window.ignoresMouseEvents = true
    window.hidesOnDeactivate = false
    window.animationBehavior = .none
    window.isReleasedWhenClosed = false

    effectView.material = .hudWindow
    effectView.blendingMode = .behindWindow
    effectView.state = .active
    effectView.maskImage = Self.roundedMask(radius: Self.cornerRadius)
    window.contentView = effectView

    // Layer-hosting view: we own this layer tree outright.
    tilesView.layer = tilesLayer
    tilesView.wantsLayer = true
    tilesLayer.addSublayer(selectionLayer)
    selectionLayer.cornerRadius = 12
    selectionLayer.cornerCurve = .continuous
    effectView.addSubview(tilesView)

    nameLabel.font = .systemFont(ofSize: 13, weight: .medium)
    nameLabel.textColor = .labelColor
    nameLabel.alignment = .center
    nameLabel.lineBreakMode = .byTruncatingTail
    effectView.addSubview(nameLabel)

    let scale = NSScreen.main?.backingScaleFactor ?? 2
    appList.iconPixelSize = Int(Self.iconSize * scale)
    appList.prewarmIcons()

    // Allocate the window's backing store now rather than on the first Cmd+Tab.
    DispatchQueue.main.async { [window] in
      window.alphaValue = 0
      window.setFrame(CGRect(x: 0, y: 0, width: 200, height: 100), display: true)
      window.orderFrontRegardless()
      window.orderOut(nil)
      window.alphaValue = 1
    }
  }

  func show(_ apps: [NSRunningApplication], selected: Int) {
    let screen = Self.screenUnderMouse()
    layout(apps, on: screen)
    select(selected)
    window.orderFrontRegardless()
  }

  func select(_ index: Int) {
    guard names.indices.contains(index) else { return }
    let tile = tileFrame(index)

    CATransaction.begin()
    CATransaction.setDisableActions(true)
    selectionLayer.frame = tile
    CATransaction.commit()

    // Size the label to the name and center it under the tile (tile frames are in tilesView's coordinates,
    // the label is in the panel's). It only shifts off-center when a long name would spill past the panel.
    nameLabel.stringValue = names[index]
    let panelWidth = effectView.bounds.width
    // cellSize includes the field's own text padding; intrinsicContentSize leaves it out and truncates.
    let labelWidth = min(ceil(nameLabel.cell!.cellSize.width), panelWidth - 2 * Self.edge)
    let tileMidX = tilesView.frame.minX + tile.midX
    let labelX = min(max(tileMidX - labelWidth / 2, Self.edge), panelWidth - Self.edge - labelWidth)
    nameLabel.frame = CGRect(x: labelX, y: Self.edge * 0.6, width: labelWidth, height: Self.labelHeight)
  }

  func hide() {
    window.orderOut(nil)
  }

  private func tileFrame(_ index: Int) -> CGRect {
    CGRect(x: CGFloat(index) * tileSize, y: 0, width: tileSize, height: tileSize)
  }

  private func layout(_ apps: [NSRunningApplication], on screen: NSScreen) {
    let pids = apps.map(\.processIdentifier)
    let screenFrame = screen.frame
    if pids == shownPids && screenFrame == shownScreenFrame {
      updateColors()
      return
    }
    shownPids = pids
    shownScreenFrame = screenFrame
    names = apps.map { $0.localizedName ?? "" }

    // Shrink icons if there are too many apps to fit on one row.
    let count = CGFloat(max(apps.count, 1))
    let maxRowWidth = screen.visibleFrame.width - 2 * Self.screenMargin - 2 * Self.edge
    let iconSize = max(16, min(Self.iconSize, maxRowWidth / count - 2 * Self.tilePadding))
    tileSize = iconSize + 2 * Self.tilePadding

    CATransaction.begin()
    CATransaction.setDisableActions(true)

    while iconLayers.count < apps.count {
      let layer = CALayer()
      layer.contentsGravity = .resizeAspect
      layer.minificationFilter = .trilinear
      tilesLayer.addSublayer(layer)
      iconLayers.append(layer)
    }
    while iconLayers.count > apps.count {
      iconLayers.removeLast().removeFromSuperlayer()
    }
    for (index, app) in apps.enumerated() {
      let layer = iconLayers[index]
      layer.frame = tileFrame(index).insetBy(dx: Self.tilePadding, dy: Self.tilePadding)
      layer.contents = appList.icon(for: app)
      layer.contentsScale = screen.backingScaleFactor
    }

    CATransaction.commit()

    let rowWidth = tileSize * count
    let size = CGSize(
      width: rowWidth + 2 * Self.edge,
      height: Self.edge + tileSize + Self.labelGap + Self.labelHeight + Self.edge * 0.6)
    let origin = CGPoint(x: screenFrame.midX - size.width / 2, y: screenFrame.midY - size.height / 2)
    window.setFrame(CGRect(origin: origin, size: size), display: false)
    tilesView.frame = CGRect(
      x: Self.edge, y: size.height - Self.edge - tileSize, width: rowWidth, height: tileSize)
    window.invalidateShadow()
    updateColors()
  }

  private func updateColors() {
    effectView.effectiveAppearance.performAsCurrentDrawingAppearance {
      selectionLayer.backgroundColor = NSColor.labelColor.withAlphaComponent(0.16).cgColor
    }
  }

  private static func screenUnderMouse() -> NSScreen {
    let mouse = NSEvent.mouseLocation
    return NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main ?? NSScreen.screens[0]
  }

  private static func roundedMask(radius: CGFloat) -> NSImage {
    let edge = 2 * radius + 1
    let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
      NSColor.black.setFill()
      NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
      return true
    }
    image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
    image.resizingMode = .stretch
    return image
  }
}

private final class NonActivatingPanel: NSPanel {
  override var canBecomeKey: Bool { false }
  override var canBecomeMain: Bool { false }
}
