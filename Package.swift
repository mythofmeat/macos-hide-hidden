// swift-tools-version: 6.0
import PackageDescription

let privateFrameworks = LinkerSetting.unsafeFlags(["-F/System/Library/PrivateFrameworks"])

let package = Package(
  name: "HideHidden",
  platforms: [.macOS(.v14)],
  targets: [
    // Vendored from MiddleClick (MoreTouch package): headers for the private MultitouchSupport.framework
    .systemLibrary(name: "MultitouchSupport"),
    .target(
      name: "MoreTouchCore",
      dependencies: ["MultitouchSupport"],
      linkerSettings: [privateFrameworks, .linkedFramework("MultitouchSupport")]
    ),
    // Vendored from MiddleClick: UserDefaults-backed config
    .target(name: "ConfigCore"),
    .executableTarget(
      name: "HideHidden",
      dependencies: ["MoreTouchCore", "MultitouchSupport", "ConfigCore"],
      linkerSettings: [privateFrameworks, .linkedFramework("SkyLight")]
    ),
  ]
)
