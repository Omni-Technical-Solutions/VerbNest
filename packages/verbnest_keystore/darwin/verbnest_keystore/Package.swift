// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "verbnest_keystore",
    platforms: [
        .iOS("15.0"),
        .macOS("12.0"),
    ],
    products: [
        .library(name: "verbnest-keystore", targets: ["verbnest_keystore"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework")
    ],
    targets: [
        .target(
            name: "verbnest_keystore",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework")
            ]
        )
    ]
)
