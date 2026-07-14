// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "DylibForge",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(
            name: "dylib-forge",
            targets: ["dylib-forge"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", exact: "1.8.2"),
        .package(url: "https://github.com/apple/swift-log.git", exact: "1.14.0"),
        .package(url: "https://github.com/JohnSundell/Files.git", exact: "4.3.0"),
        .package(url: "https://github.com/swiftlang/swift-subprocess.git", exact: "1.0.0-beta.1"),
        .package(url: "https://github.com/nicklockwood/SwiftFormat", exact: "0.62.1"),
        .package(url: "https://github.com/jpsim/Yams.git", exact: "6.2.2"),
    ],
    targets: [
        .target(
            name: "DylibForgeCore",
            dependencies: [
                .product(name: "Files", package: "Files"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "Subprocess", package: "swift-subprocess"),
                .product(name: "Yams", package: "Yams"),
            ]
        ),
        .executableTarget(
            name: "dylib-forge",
            dependencies: [
                "DylibForgeCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Logging", package: "swift-log"),
            ]
        ),
    ]
)
