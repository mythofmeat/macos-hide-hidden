# frozen_string_literal: true

# This repository is its own tap. It is private, so tap it over SSH:
#   brew tap mythofmeat/hide-hidden git@github.com:mythofmeat/macos-hide-hidden.git
#   brew install mythofmeat/hide-hidden/hide-hidden
# The formula clones over SSH too: Homebrew fetches inside a sandbox that hides
# the login keychain, so HTTPS credentials kept there never reach git.
# The release workflow moves the tag below with every release.
class HideHidden < Formula
  desc "Cmd+Tab switcher that skips hidden apps, plus three-finger middle click"
  homepage "https://github.com/mythofmeat/macos-hide-hidden"
  url "ssh://git@github.com/mythofmeat/macos-hide-hidden.git",
      tag: "v0.1.0"
  license "GPL-3.0-only"
  head "ssh://git@github.com/mythofmeat/macos-hide-hidden.git", branch: "main"

  depends_on macos: :sonoma

  def install
    # The sandbox also hides the signing certificate, so this build is always signed ad hoc.
    system "make", "app", "VERSION=#{version}", "SWIFT_BUILD_FLAGS=--disable-sandbox"
    prefix.install "build/HideHidden.app"
  end

  # Started from the opt path, which stays put across upgrades. Quitting from the menu bar
  # exits cleanly and stays quit; only a crash brings it back.
  service do
    run opt_prefix/"HideHidden.app/Contents/MacOS/HideHidden"
    keep_alive crashed: true
    process_type :interactive
  end

  def caveats
    <<~EOS
      Start it now and at every login:
        brew services start hide-hidden

      Then allow it in System Settings > Privacy & Security > Accessibility. If it
      isn't listed, add #{opt_prefix}/HideHidden.app with the + button.

      Every build is signed ad hoc, so after an upgrade remove it from that list,
      add it again, and run `brew services restart hide-hidden`.
    EOS
  end

  test do
    plist = prefix/"HideHidden.app/Contents/Info.plist"
    assert_equal version.to_s,
                 shell_output("/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' #{plist}").strip
  end
end
