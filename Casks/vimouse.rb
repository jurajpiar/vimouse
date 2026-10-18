cask "vimouse" do
  version "0.0.0"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"

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
