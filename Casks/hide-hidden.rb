# This repository is its own tap:
#   brew tap mythofmeat/hide-hidden https://github.com/mythofmeat/macos-hide-hidden
#   brew install --cask mythofmeat/hide-hidden/hide-hidden
# The release workflow's `cask` job rewrites version and sha256 after it has
# uploaded the zip, so this file always names the newest published release.
cask "hide-hidden" do
  version "0.1.0"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"

  url "https://github.com/mythofmeat/macos-hide-hidden/releases/download/v#{version}/HideHidden-#{version}-arm64.zip"
  name "HideHidden"
  desc "Cmd+Tab switcher that skips hidden apps, plus three-finger middle click"
  homepage "https://github.com/mythofmeat/macos-hide-hidden"

  depends_on arch: :arm64
  depends_on macos: :sonoma

  app "HideHidden.app"

  # The bundle is signed ad hoc, not notarised, so Gatekeeper refuses to open a
  # quarantined copy. Steps take {{appdir}}, not Ruby interpolation, and run
  # sandboxed: the app is the only thing xattr may write.
  postflight_steps do
    run "/usr/bin/xattr",
        args:           ["-dr", "com.apple.quarantine", "{{appdir}}/HideHidden.app"],
        writable_paths: ["HideHidden.app"],
        writable_base:  :appdir
  end

  # A signal rather than `quit:`, which would make macOS ask permission for the
  # terminal to control the app. It keeps no state, so TERM is a clean exit.
  uninstall signal: [["TERM", "com.mythofmeat.HideHidden"]]

  zap trash: "~/Library/Preferences/com.mythofmeat.HideHidden.plist"

  caveats <<~EOS
    Allow HideHidden in System Settings > Privacy & Security > Accessibility,
    and turn on "Launch at login" from its menu bar icon.

    Each release is signed ad hoc, so after an upgrade remove HideHidden from the
    Accessibility list, add it again, and reopen it.
  EOS
end
