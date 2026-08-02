import Foundation

/// A fixture framework that exercises one static-to-dynamic conversion scenario.
enum Fixture: String, CaseIterable, Sendable {
    /// An Objective-C class whose implementation uses private visibility.
    case privateObjC = "StaticFrameworkWithPrivateObjC"
    /// A framework that contains and calls a C++ static dependency.
    case cxxDependency = "StaticFrameworkWithCxxDependency"
    /// A framework with duplicate native definitions that need de-duplication.
    case duplicateSymbols = "StaticFrameworkWithDuplicateSymbols"
    /// A framework with an intentionally excluded object file.
    case excludedObject = "StaticFrameworkWithExcludedObject"
    /// A framework composed entirely of Swift source.
    case swift = "StaticFrameworkWithSwift"
    /// A Swift framework consumed by another Swift fixture framework.
    case swiftDependency = "StaticFrameworkWithSwiftDependency"
    /// A Swift framework that imports the Swift dependency fixture.
    case swiftDependentFramework = "StaticFrameworkWithSwiftDependentFramework"
    /// A framework composed entirely of Objective-C source.
    case objectiveC = "StaticFrameworkWithObjC"
    /// A framework that combines Objective-C and Swift source.
    case objectiveCAndSwift = "StaticFrameworkWithObjCAndSwift"

    /// Additional `dylib-forge-xc` arguments required by this scenario.
    var relinkingArguments: [String] {
        switch self {
        case .excludedObject:
            ["--exclude-object-sdk", "any", "--exclude-object-sdk", "ReleaseOnlyGhost"]
        default:
            []
        }
    }

    /// Relinked XCFrameworks that must be supplied while rebuilding this fixture.
    var xcframeworkDependencies: [Fixture] {
        switch self {
        case .swiftDependentFramework:
            [.swiftDependency]
        default:
            []
        }
    }
}

/// An Apple platform slice included in every fixture XCFramework.
enum Platform: String, CaseIterable, Sendable {
    /// The macOS device platform.
    case macOS
    /// The iOS device platform.
    case iOS
    /// The iOS Simulator platform.
    case iOSSimulator
    /// The watchOS device platform.
    case watchOS
    /// The watchOS Simulator platform.
    case watchOSSimulator

    /// The `xcodebuild` SDK name for this platform.
    var sdk: String {
        switch self {
        case .macOS: "macosx"
        case .iOS: "iphoneos"
        case .iOSSimulator: "iphonesimulator"
        case .watchOS: "watchos"
        case .watchOSSimulator: "watchsimulator"
        }
    }

    /// The generic `xcodebuild` destination for this platform.
    var destination: String {
        switch self {
        case .macOS: "generic/platform=macOS"
        case .iOS: "generic/platform=iOS"
        case .iOSSimulator: "generic/platform=iOS Simulator"
        case .watchOS: "generic/platform=watchOS"
        case .watchOSSimulator: "generic/platform=watchOS Simulator"
        }
    }
}

extension Platform {
    var relinkingArguments: [String] {
        switch self {
        case .macOS:
            ["--linker-arg-sdk", "macosx", "--linker-arg-sdk", "-mmacosx-version-min=15.0"]
        case .iOS:
            ["--linker-arg-sdk", "iphoneos", "--linker-arg-sdk", "-miphoneos-version-min=16.0"]
        case .iOSSimulator:
            ["--linker-arg-sdk", "iphonesimulator", "--linker-arg-sdk", "-mios-simulator-version-min=16.0"]
        case .watchOS:
            ["--linker-arg-sdk", "watchos", "--linker-arg-sdk", "-mwatchos-version-min=9.0"]
        case .watchOSSimulator:
            ["--linker-arg-sdk", "watchsimulator", "--linker-arg-sdk", "-mwatchos-simulator-version-min=9.0"]
        }
    }
}
