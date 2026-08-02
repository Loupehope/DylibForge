// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "DylibForge",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        .executable(
            name: "dylib-forge",
            targets: ["dylib-forge"],
        ),
        .executable(
            name: "dylib-forge-xc",
            targets: ["dylib-forge-xc"],
        ),
        .executable(
            name: "dylib-forge-tests",
            targets: ["dylib-forge-tests"],
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", exact: "1.8.2"),
        .package(url: "https://github.com/apple/swift-log.git", exact: "1.14.0"),
        .package(url: "https://github.com/swiftlang/swift-subprocess.git", exact: "1.0.0-beta.1"),
        .package(url: "https://github.com/nicklockwood/SwiftFormat", exact: "0.62.1"),
        .package(url: "https://github.com/jpsim/Yams.git", exact: "6.2.2"),
    ],
    targets: [
        .target(
            name: "DylibForgeSubprocess",
            dependencies: [
                .product(name: "Logging", package: "swift-log"),
                .product(name: "Subprocess", package: "swift-subprocess"),
            ],
        ),
        .target(
            name: "DylibForgeCore",
            dependencies: [
                "DylibForgeSubprocess",
                .product(name: "Logging", package: "swift-log"),
                .product(name: "Yams", package: "Yams"),
            ],
        ),
        .executableTarget(
            name: "dylib-forge",
            dependencies: [
                "DylibForgeCore",
                "DylibForgeSubprocess",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Logging", package: "swift-log"),
            ],
        ),
        .target(
            name: "DylibForgeXCFramework",
            dependencies: [
                "DylibForgeCore",
                "DylibForgeSubprocess",
                .product(name: "Logging", package: "swift-log"),
            ],
        ),
        .executableTarget(
            name: "dylib-forge-xc",
            dependencies: [
                "DylibForgeXCFramework",
                "DylibForgeCore",
                "DylibForgeSubprocess",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Logging", package: "swift-log"),
            ],
        ),
        .target(
            name: "DylibForgeAcceptanceTests",
            dependencies: [
                "DylibForgeSubprocess",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Logging", package: "swift-log"),
            ],
        ),
        .executableTarget(
            name: "dylib-forge-tests",
            dependencies: [
                "DylibForgeAcceptanceTests",
                "DylibForgeSubprocess",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Logging", package: "swift-log"),
            ],
        ),
    ],
)
