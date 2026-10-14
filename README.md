# HideHidden

A tiny menu bar app that does two things:

1. **Cmd+Tab shows only what's on this desktop.** A replacement for the native app switcher that lists only
   apps with a window on the current desktop, so hidden apps, windowless apps (yes, Finder), minimized-only
   apps, and apps on other desktops or in fullscreen stay out. Otherwise it behaves like the native one:
   most-recent order, Tab / Shift+Tab / `` ` `` / arrows to move, Esc to cancel, release Cmd to switch. Its
   only other goal is to be fast.
2. **Three-finger click/tap = middle click.** This is [MiddleClick](https://github.com/artginzburg/MiddleClick)
   (GPL-3.0, upstream is finished), vendored in so it can be fixed here when macOS changes.

## Install

The repo is its own Homebrew tap:

```bash
brew tap mythofmeat/hide-hidden https://github.com/mythofmeat/macos-hide-hidden
brew install --cask mythofmeat/hide-hidden/hide-hidden
```

That installs `/Applications/HideHidden.app` (Apple silicon, macOS 14+). Open it, grant it **Accessibility**
in System Settings → Privacy & Security → Accessibility (both features need it), and turn on
**Launch at login** from its menu bar icon.

Updating: `brew upgrade --cask hide-hidden` quits the app, replaces it, and reopens it. Then re-grant
Accessibility (see below).

### Building from a checkout

Needs the Xcode Command Line Tools (`xcode-select --install`), not full Xcode.

```bash
make install
```

That builds `build/HideHidden.app`, copies it over `/Applications/HideHidden.app`, and launches it.

### Stop re-granting Accessibility after every rebuild (optional, one-time)

macOS ties the Accessibility grant to the app's code signature. With no signing certificate the build is
ad-hoc signed, so every rebuild looks like a new app and you have to remove and re-add it in Settings.

To fix that, create a free self-signed certificate once:

1. Open **Keychain Access** → menu **Keychain Access → Certificate Assistant → Create a Certificate…**
2. Name: `HideHidden Signing`, Identity Type: **Self Signed Root**, Certificate Type: **Code Signing**
3. Click **Create**

The Makefile picks it up automatically (`make app` prints which identity it signed with). Do this before
granting Accessibility, or remove the old entry and add it again once. This only helps local `make` builds:
the releases the cask installs are built and signed ad hoc on GitHub Actions.

## Trackpad settings

From MiddleClick: in System Settings → Trackpad, turn off **Look up & data detectors → Tap with Three
Fingers** if you use tap-to-middle-click, and avoid **three-finger drag** (Accessibility → Pointer
Control). The app warns you about both on first launch.

## Known behavior

- **Password fields:** while a secure text field is focused, macOS hides keystrokes from all event taps
  ("Secure Input"), so the native switcher appears instead. That's intentional: the native shortcut is
  never disabled, so if this app quits or crashes, Cmd+Tab still works.
- **Fullscreen apps:** a fullscreen app is its own desktop, so inside one, Cmd+Tab lists only that app. Use
  Ctrl+arrow or Mission Control to leave it.
- App-level only (no per-window switching), one row of icons centered on the screen under the mouse.
- The menu bar toggle **Replace native switcher** turns all of this off and gives you the stock Cmd+Tab back.

## Layout

```
Sources/
  HideHidden/
    main.swift                 entry point
    App/TrayMenu.swift         menu bar menu (adapted from MiddleClick)
    Switcher/
      SwitcherKeyTap.swift     intercepts Cmd+Tab (HID event tap)
      Switcher.swift           session state + app activation
      SwitcherPanel.swift      the overlay UI
      AppList.swift            most-recently-used app order + icon cache
    MiddleClick/               vendored MiddleClick app code (lightly modified)
  MoreTouchCore/, MultitouchSupport/, ConfigCore/   vendored MiddleClick packages
```

Useful targets: `make run` (build and launch from `build/`), `make logs` (stream the app's logs),
`make uninstall`.

## Releasing

Run the **release** workflow from the Actions tab (pick patch/minor/major). It bumps the version in the
`Makefile`, commits `chore(release): vX.Y.Z` and tags it, builds and zips the app on a macOS runner, publishes
the GitHub release with the zip, and then points the cask at it in a `chore(release): cask vX.Y.Z` commit.
Then `brew upgrade --cask hide-hidden`.

## Credits and license

GPL-3.0 (see `LICENSE`).

- **[MiddleClick](https://github.com/artginzburg/MiddleClick)** by Arthur Ginzburg and contributors (GPL-3.0)
  is vendored from commit `566155d` (v3.3.0). Changes, also noted at the top of each changed file:
  - Replaced `main.swift`.
  - Dropped `UserDefaultsMigration.swift`.
  - `TrayMenu`: removed the successor/promo items and the pre-macOS-13 fallbacks, swapped the asset-catalog
    status icon for an SF Symbol, and added the switcher toggle.
  - `IOMultitouchManager`: `kIOMasterPortDefault` → `kIOMainPortDefault`.
- **[AltTab](https://github.com/lwouis/alt-tab-macos)** by Louis Pontoise and contributors (GPL-3.0) is where
  the switcher's approach comes from: activating apps with `NSRunningApplication.activate`, falling back to the
  private `_SLPSSetFrontProcessWithOptions` call (declaration and flags follow AltTab's), and its notes on how
  the native Cmd+Tab is matched and how Secure Input affects event taps.
