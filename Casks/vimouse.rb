cask "vimouse" do
  version "0.0.0"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"

  url "https://github.com/jurajpiar/vimouse/releases/download/v#{version}/vimouse-#{version}.zip"
  name "vimouse"
  desc "Keyboard-driven mouse: quadrant navigation, scrolling, a reading ruler and more"
  homepage "https://github.com/jurajpiar/vimouse"

  depends_on macos: ">= :sonoma"

  app "vimouse.app"

  postflight do
    system_command "/usr/bin/open", args: ["-a", "#{appdir}/vimouse.app"]
  end

  uninstall quit: "com.jurajpiar.vimouse"

  zap trash: [
    "~/.config/vimouse",
  ]

  caveats <<~EOS
    vimouse needs Accessibility access: System Settings > Privacy & Security >
    Accessibility. Its settings live in ~/.config/vimouse/config.toml.
  EOS
end
