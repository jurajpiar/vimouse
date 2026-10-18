cask "vimouse" do
  version "0.1.0"
  sha256 "634416a4e589c111e2854545934a71a25a4f51aecf0adeb8199f4a28c5a816ef"

  url "https://github.com/jurajpiar/vimouse/releases/download/v#{version}/vimouse-#{version}.zip"
  name "vimouse"
  desc "Keyboard-driven mouse: quadrant navigation, scrolling, a reading ruler and more"
  homepage "https://github.com/jurajpiar/vimouse"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: ">= :sonoma"

  app "vimouse.app"

  uninstall quit: "com.jurajpiar.vimouse"

  zap trash: [
    "~/.config/vimouse",
  ]

  caveats <<~EOS
    vimouse needs Accessibility access: System Settings > Privacy & Security >
    Accessibility. Its settings live in ~/.config/vimouse/config.toml.
    Start it from /Applications; "Launch at login" is in its menu bar menu.
  EOS
end
