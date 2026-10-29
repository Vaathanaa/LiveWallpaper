// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "VideoBackdrop",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "VideoBackdrop", targets: ["VideoBackdrop"])
    ],
    targets: [
        .executableTarget(
            name: "VideoBackdrop",
            path: "Sources"
        )
    ]
)
