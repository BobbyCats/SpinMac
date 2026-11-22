// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SpinMac",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "SpinMac", targets: ["SpinMacApp"]),
        .library(name: "SpinMacCore", targets: ["SpinMacCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "2.2.4"),
    ],
    targets: [
        .target(
            name: "CMultitouch",
            path: "Sources/CMultitouch",
            publicHeadersPath: "include"
        ),
        .target(
            name: "SpinMacCore",
            dependencies: ["CMultitouch"],
            path: "Sources/SpinMacCore",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("IOKit"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
        .executableTarget(
            name: "SpinMacApp",
            dependencies: [
                "SpinMacCore",
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
            ],
            path: "Sources/SpinMacApp",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "SpinMacCoreTests",
            dependencies: ["SpinMacCore"],
            path: "Tests/SpinMacCoreTests"
        ),
    ]
)
