cask "livewallpaper" do
  version "1.2.0"
  sha256 :no_check

  url "https://github.com/Vaathanaa/LiveWallpaper/releases/download/v#{version}/LiveWallpaper-v#{version}.dmg"
  name "LiveWallpaper"
  desc "Ultra-performance hardware-accelerated dynamic live wallpaper engine for Apple Silicon"
  homepage "https://github.com/Vaathanaa/LiveWallpaper"

  livecheck do
    url :url
    strategy :github_latest
  end

  auto_updates true
  depends_on macos: ">= :ventura"
  depends_on arch: :arm64

  app "LiveWallpaper.app"

  zap trash: [
    "~/Library/Application Support/LiveWallpaper",
    "~/Library/Preferences/com.local.LiveWallpaper.plist",
    "~/Library/Caches/com.local.LiveWallpaper",
  ]
end
