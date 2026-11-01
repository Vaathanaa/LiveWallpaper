// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LiveWallpaper",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "LiveWallpaper", targets: ["LiveWallpaper"])
    ],
    targets: [
        .executableTarget(
            name: "LiveWallpaper",
            path: "Sources"
        ),
        .testTarget(
            name: "LiveWallpaperTests",
            dependencies: ["LiveWallpaper"],
            path: "Tests/LiveWallpaperTests"
        )
    ]
)
