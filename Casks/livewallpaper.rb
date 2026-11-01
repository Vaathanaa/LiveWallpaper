cask "livewallpaper" do
  version "1.2.2"
  sha256 :no_check

  url "https://github.com/Vaathanaa/LiveWallpaper/releases/download/v#{version}/LiveWallpaper-#{version}.dmg"
  name "LiveWallpaper"
  desc "120Hz hardware-accelerated live video wallpaper and aerial screen saver engine"
  homepage "https://github.com/Vaathanaa/LiveWallpaper"

  livecheck do
    url :url
    strategy :github_latest
  end

  auto_updates true
  depends_on macos: ">= :ventura"
  depends_on arch: :arm64

  app "LiveWallpaper.app"
  screen_saver "LiveWallpaper.saver"

  postflight do
    system_command "/usr/bin/xattr",
                   args: ["-cr", "#{appdir}/LiveWallpaper.app"]
  end

  zap trash: [
    "~/Library/Application Support/LiveWallpaper",
    "~/Library/Preferences/com.local.LiveWallpaper.plist",
    "~/Library/Caches/com.local.LiveWallpaper",
    "~/Library/Screen Savers/LiveWallpaper.saver",
  ]
end
