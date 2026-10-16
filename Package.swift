// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "vimouse",
    platforms: [.macOS(.v14)],
    targets: [
        // Platform-independent logic: geometry, bisect session, key handling, engine.
        .target(name: "VimouseCore", path: "Sources/VimouseCore"),
        // The macOS app: event tap, overlay windows, pointer control, menu bar.
        .executableTarget(
            name: "vimouse",
            dependencies: ["VimouseCore"],
            path: "Sources/VimouseMac"
        ),
        .testTarget(name: "VimouseCoreTests", dependencies: ["VimouseCore"], path: "Tests/VimouseCoreTests"),
    ]
)
