# Template for Casks/swiftcast.rb in inhzus/homebrew-tap. The release workflow fills in
# version and sha256 and pushes it there.
cask "swiftcast" do
  version "0.1.0"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"

  url "https://github.com/inhzus/swiftcast/releases/download/v#{version}/SwiftCast-#{version}.zip"
  name "SwiftCast"
  desc "Fast, native app launcher"
  homepage "https://github.com/inhzus/swiftcast"

  depends_on macos: :tahoe

  app "SwiftCast.app"

  # Builds are ad-hoc signed, not notarized, so Gatekeeper would block the first launch.
  # Remove this once releases are notarized.
  postflight_steps do
    run "/usr/bin/xattr",
        args:           ["-dr", "com.apple.quarantine", "{{appdir}}/SwiftCast.app"],
        writable_paths: ["{{appdir}}/SwiftCast.app"]
  end

  uninstall quit: "dev.swiftcast.app"

  zap trash: "~/Library/Preferences/dev.swiftcast.app.plist"

  caveats <<~EOS
    SwiftCast's default shortcut, ⌘Space, is taken by Spotlight. Either turn off Spotlight's
    shortcut in System Settings → Keyboard → Keyboard Shortcuts → Spotlight, or pick another
    shortcut in SwiftCast's Settings (⌘,).
  EOS
end
