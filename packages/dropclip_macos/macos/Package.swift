// swift-tools-version: 5.9
// The Flutter-free core of the macOS plugin (T1.6). Built and tested on its
// own with `swift test`; the Flutter plugin compiles the same sources.
import PackageDescription

let package = Package(
    name: "DropClipMacCore",
    platforms: [.macOS(.v12)],
    products: [
        .library(name: "DropClipMacCore", targets: ["DropClipMacCore"]),
    ],
    targets: [
        .target(name: "DropClipMacCore", path: "Classes/Core"),
        .testTarget(
            name: "DropClipMacCoreTests",
            dependencies: ["DropClipMacCore"],
            path: "Tests"
        ),
    ]
)
