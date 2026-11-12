// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "dropclip_macos",
    platforms: [.macOS(.v12)],
    products: [
        .library(name: "dropclip-macos", targets: ["dropclip_macos"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework")
    ],
    targets: [
        .target(
            name: "dropclip_macos",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework")
            ]
        )
    ]
)
