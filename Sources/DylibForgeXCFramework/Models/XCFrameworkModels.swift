import DylibForgeCore
import Foundation

/// Root XCFramework property list while preserving every field not owned by this tool.
///
/// XCFramework manifests can contain vendor-defined keys. This wrapper only changes `AvailableLibraries`, retaining
/// all other root metadata when it is serialized back to disk.
struct XCFrameworkManifest {
    private var rawPropertyList: [String: Any]

    /// Validates and wraps the decoded root property-list dictionary.
    init(propertyList: [String: Any]) throws {
        guard let rawLibraries = propertyList["AvailableLibraries"] as? [[String: Any]] else {
            throw DylibForgeError.message("XCFramework Info.plist has no AvailableLibraries array")
        }
        rawPropertyList = propertyList
        availableLibraries = try rawLibraries.map(XCFrameworkLibrary.init)
    }

    /// Platform-specific library entries; assigning this also writes their raw forms back into the manifest.
    var availableLibraries: [XCFrameworkLibrary] {
        didSet {
            rawPropertyList["AvailableLibraries"] = availableLibraries.map(\.propertyList)
        }
    }

    /// Full property-list dictionary ready for serialization.
    var encodedPropertyList: [String: Any] {
        rawPropertyList
    }
}

/// One platform-specific artifact entry from an XCFramework manifest.
///
/// The raw property list is kept intact so headers, debug-symbol paths, architectures, and future Xcode keys survive
/// conversion unchanged.
struct XCFrameworkLibrary {
    private var rawPropertyList: [String: Any]

    /// Artifact path relative to ``identifier``.
    private(set) var libraryPath: String

    /// Relinking strategy inferred from the artifact extension.
    private(set) var artifactKind: XCFrameworkArtifactKind

    /// Directory name containing this platform-specific artifact.
    let identifier: String

    /// Platform spelling stored by Xcode, for example `ios` or `watchos`.
    let supportedPlatform: String?

    /// Optional Xcode platform variant, such as `simulator` or `maccatalyst`.
    let supportedPlatformVariant: String?

    /// Architectures covered by this artifact entry.
    let supportedArchitectures: [String]

    /// Validates the fields necessary to locate an artifact inside the XCFramework.
    init(propertyList: [String: Any]) throws {
        guard let identifier = propertyList["LibraryIdentifier"] as? String,
              let libraryPath = propertyList["LibraryPath"] as? String,
              !identifier.isEmpty,
              !libraryPath.isEmpty
        else {
            throw DylibForgeError.message("Each AvailableLibraries item must contain LibraryIdentifier and LibraryPath")
        }
        rawPropertyList = propertyList
        self.identifier = identifier
        self.libraryPath = libraryPath
        supportedPlatform = propertyList["SupportedPlatform"] as? String
        supportedPlatformVariant = propertyList["SupportedPlatformVariant"] as? String
        supportedArchitectures = propertyList["SupportedArchitectures"] as? [String] ?? []
        artifactKind = XCFrameworkArtifactKind(path: libraryPath)
    }

    /// Original entry data plus any conversion-specific updates.
    var propertyList: [String: Any] {
        rawPropertyList
    }

    /// Resolves the artifact's absolute location inside an XCFramework copy.
    func artifactURL(in xcframeworkURL: URL) throws -> URL {
        let rootURL = xcframeworkURL.standardizedFileURL.resolvingSymlinksInPath()
        return rootURL
            .appendingPathComponent(identifier, isDirectory: true)
            .appendingPathComponent(libraryPath)
            .standardizedFileURL
            .resolvingSymlinksInPath()
    }

    /// Records that a static archive has been replaced with a dynamic library.
    ///
    /// `BinaryPath` is static-library metadata and must not survive after `LibraryPath` starts pointing to a dylib.
    mutating func replaceStaticArchive(with dylibURL: URL) {
        libraryPath = dylibURL.lastPathComponent
        artifactKind = .other
        rawPropertyList["LibraryPath"] = libraryPath
        rawPropertyList.removeValue(forKey: "BinaryPath")
    }

    /// Updates Xcode's architecture metadata after legacy slices were omitted by the active toolchain.
    mutating func replaceSupportedArchitectures(with architectures: [String]) {
        rawPropertyList["SupportedArchitectures"] = architectures
    }
}

/// Artifact forms relevant to relinking inside an XCFramework.
enum XCFrameworkArtifactKind: Equatable {
    case staticArchive
    case framework
    case other

    /// Classifies the artifact from its path extension without inspecting its bytes.
    init(path: String) {
        switch URL(fileURLWithPath: path).pathExtension {
        case "a":
            self = .staticArchive
        case "framework":
            self = .framework
        default:
            self = .other
        }
    }
}

/// Framework bundle data needed to locate its binary and select its SDK.
struct XCFrameworkBundleInfo {
    let executableName: String
    let platformName: String?

    /// Extracts the executable and optional Xcode platform name from a framework `Info.plist`.
    init(propertyList: [String: Any], frameworkURL: URL) throws {
        guard let executableName = propertyList["CFBundleExecutable"] as? String, !executableName.isEmpty else {
            throw DylibForgeError.message("Framework Info.plist has no CFBundleExecutable: \(frameworkURL.path)")
        }
        self.executableName = executableName
        platformName = propertyList["DTPlatformName"] as? String
    }
}
