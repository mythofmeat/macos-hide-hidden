# HideHidden

A tiny menu bar app that does two things:

1. **Cmd+Tab skips hidden apps.** A replacement for the native app switcher that leaves out apps you've
   hidden with Cmd+H. Otherwise it behaves like the native one: same apps, most-recent order, Tab /
   Shift+Tab / `` ` `` / arrows to move, Esc to cancel, release Cmd to switch. Its only other goal is to be fast.
2. **Three-finger click/tap = middle click.** This is [MiddleClick](https://github.com/artginzburg/MiddleClick)
   (GPL-3.0, upstream is finished), vendored in so it can be fixed here when macOS changes.

## Install

The repo is private and is its own Homebrew tap, so tap it over SSH:

```bash
brew tap mythofmeat/hide-hidden git@github.com:mythofmeat/macos-hide-hidden.git
brew install mythofmeat/hide-hidden/hide-hidden
brew services start hide-hidden
```

Then grant it **Accessibility** in System Settings → Privacy & Security → Accessibility. Both features
need it. If it isn't listed, add `$(brew --prefix)/opt/hide-hidden/HideHidden.app` with the + button.

`brew services` starts it at login and restarts it if it crashes. Quitting from the menu bar keeps it quit
until the next login or `brew services restart hide-hidden`. Leave the menu's **Launch at login** off when
using brew services. (A second copy would just exit, but there's no point.)

Updating: `brew upgrade hide-hidden`, then re-grant Accessibility (see below) and
`brew services restart hide-hidden`.

### Building from a checkout

Needs the Xcode Command Line Tools (`xcode-select --install`), not full Xcode.

```bash
make install
```

That builds `build/HideHidden.app`, copies it to `/Applications`, and launches it. Use either this or the
brew install, not both.

### Stop re-granting Accessibility after every rebuild (optional, one-time)

macOS ties the Accessibility grant to the app's code signature. With no signing certificate the build is
ad-hoc signed, so every rebuild looks like a new app and you have to remove and re-add it in Settings.

To fix that, create a free self-signed certificate once:

1. Open **Keychain Access** → menu **Keychain Access → Certificate Assistant → Create a Certificate…**
2. Name: `HideHidden Signing`, Identity Type: **Self Signed Root**, Certificate Type: **Code Signing**
3. Click **Create**

The Makefile picks it up automatically (`make app` prints which identity it signed with). Do this before
granting Accessibility, or remove the old entry and add it again once. This only helps `make` builds:
Homebrew builds in a sandbox that hides the keychain, so brew installs are always signed ad hoc.

## Trackpad settings

From MiddleClick: in System Settings → Trackpad, turn off **Look up & data detectors → Tap with Three
Fingers** if you use tap-to-middle-click, and avoid **three-finger drag** (Accessibility → Pointer
Control). The app warns you about both on first launch.

## Known behavior

- **Password fields:** while a secure text field is focused, macOS hides keystrokes from all event taps
  ("Secure Input"), so the native switcher appears instead. That's intentional: the native shortcut is
  never disabled, so if this app quits or crashes, Cmd+Tab still works.
- App-level only (no per-window switching), one row of icons centered on the screen under the mouse.

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

Run the **release** workflow from the Actions tab (pick patch/minor/major). It builds, bumps the version in
the `Makefile` and the formula's tag, commits `chore(release): vX.Y.Z`, tags it, and creates a GitHub release.
Then `brew upgrade hide-hidden`.

## Credits and license

GPL-3.0 (see `LICENSE`), because it includes MiddleClick by Arthur Ginzburg and contributors, vendored from
commit `566155d` (v3.3.0). Changes to the vendored code:
- Replaced `main.swift`.
- Dropped `UserDefaultsMigration.swift`.
- `TrayMenu`: removed the successor/promo items and the pre-macOS-13 fallbacks, swapped the asset-catalog
  status icon for an SF Symbol, and added the switcher toggle.
- `kIOMasterPortDefault` → `kIOMainPortDefault`.
