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
            name: "dylib-forge-tests",
            targets: ["dylib-forge-tests"],
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", exact: "1.8.2"),
        .package(url: "https://github.com/swiftlang/swift-subprocess.git", exact: "1.0.0"),
        .package(url: "https://github.com/jpsim/Yams.git", exact: "6.2.2"),
    ],
    targets: [
        .target(
            name: "DylibForgeCore",
            dependencies: [
                .product(name: "Subprocess", package: "swift-subprocess"),
            ],
        ),
        .target(
            name: "DylibForgeArchive",
            dependencies: [
                "DylibForgeCore",
                .product(name: "Yams", package: "Yams"),
            ],
        ),
        .target(
            name: "DylibForgeXCFramework",
            dependencies: [
                "DylibForgeCore",
                "DylibForgeArchive",
            ],
        ),
        .executableTarget(
            name: "dylib-forge",
            dependencies: [
                "DylibForgeArchive",
                "DylibForgeCore",
                "DylibForgeXCFramework",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
        ),
        .target(
            name: "DylibForgeAcceptanceTests",
            dependencies: [
                "DylibForgeCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
        ),
        .executableTarget(
            name: "dylib-forge-tests",
            dependencies: [
                "DylibForgeAcceptanceTests",
                "DylibForgeCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
        ),
    ],
)
