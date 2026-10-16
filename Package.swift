// swift-tools-version: 5.10
import PackageDescription

// Modes are plugins: one target each, depending only on VimouseCore. To add one, add a
// target here and register it in Sources/VimouseMac/main.swift (and in the tests'
// `standardModes` if it should be covered there). To drop one, remove it from both.
let modes = ["Pointer", "Nudge", "Scroll", "Ruler"]

let package = Package(
    name: "vimouse",
    platforms: [.macOS(.v14)],
    targets: [
        // Platform-independent logic: geometry, keys, config, the engine and the mode interface.
        .target(name: "VimouseCore", path: "Sources/VimouseCore"),
    ] + modes.map {
        .target(name: "\($0)Mode", dependencies: ["VimouseCore"], path: "Sources/Modes/\($0)")
    } + [
        // The macOS app: event tap, overlay windows, pointer control, menu bar.
        .executableTarget(
            name: "vimouse",
            dependencies: ["VimouseCore"] + modes.map { .target(name: "\($0)Mode") },
            path: "Sources/VimouseMac"
        ),
        .testTarget(
            name: "VimouseCoreTests",
            dependencies: ["VimouseCore"] + modes.map { .target(name: "\($0)Mode") },
            path: "Tests/VimouseCoreTests"
        ),
    ]
)
