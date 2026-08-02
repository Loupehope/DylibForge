import Foundation

/// Describes the target binary artifact that will be rebuilt as a dynamic binary.
struct RelinkTarget {
    let inputURL: URL
    let binaryURL: URL
    let outputBinaryName: String
    let sdk: String
}

/// Dependencies and search paths for the final `clang -dynamiclib` invocation.
struct AutolinkDirectives {
    let frameworkPaths: Set<String>
    let libraryPaths: Set<String>
    let frameworks: Set<String>
    let weakFrameworks: Set<String>
    let libraries: Set<String>
    let weakLibraries: Set<String>
}

/// Architecture information for the input binary.
struct ArchitectureSlices {
    let architectures: [String]
    let isUniversal: Bool
}

/// Result of unpacking a static archive into object files.
struct ExtractedObjects {
    let objectFiles: [URL]
}

/// Result of relinking one binary, including architecture slices omitted by the active Xcode toolchain.
public struct RelinkResult: Sendable {
    public let linkedArchitectures: [String]
    public let skippedArchitectures: [String]

    public init(linkedArchitectures: [String], skippedArchitectures: [String]) {
        self.linkedArchitectures = linkedArchitectures
        self.skippedArchitectures = skippedArchitectures
    }
}

/// Resolved inputs for linking one architecture slice.
struct DynamicSliceLinkContext {
    let sdk: String
    let sdkPath: String
    let targetTriples: SDKTargetTriples
    let frameworkSearchRoots: [URL]
    let architecture: String
    let objectFiles: [URL]
    let outputFile: URL
    let installName: String
    let autolinkDirectives: AutolinkDirectives
    let linkerArgs: [String]

    var linkedProductName: String {
        URL(fileURLWithPath: installName).lastPathComponent
    }
}

/// Partial `swiftc -print-target-info` output used to discover Swift runtime search paths.
struct SwiftTargetInfo: Decodable {
    let paths: SwiftTargetPaths
}

/// Path payload inside `swiftc -print-target-info`.
struct SwiftTargetPaths: Decodable {
    let runtimeLibraryPaths: [String]
}

/// Partial `SDKSettings.plist` model for the SDK selected through `xcrun --sdk`.
struct SDKSettings: Decodable {
    let supportedTargets: [String: SDKSupportedTarget]

    enum CodingKeys: String, CodingKey {
        case supportedTargets = "SupportedTargets"
    }
}

/// Target-triple metadata from one `SupportedTargets` entry in `SDKSettings.plist`.
struct SDKSupportedTarget: Decodable {
    let llvmTargetTripleVendor: String
    let llvmTargetTripleSys: String
    let llvmTargetTripleEnvironment: String?
    let defaultDeploymentTarget: String

    enum CodingKeys: String, CodingKey {
        case llvmTargetTripleVendor = "LLVMTargetTripleVendor"
        case llvmTargetTripleSys = "LLVMTargetTripleSys"
        case llvmTargetTripleEnvironment = "LLVMTargetTripleEnvironment"
        case defaultDeploymentTarget = "DefaultDeploymentTarget"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        llvmTargetTripleVendor = try container.decode(String.self, forKey: .llvmTargetTripleVendor)
        llvmTargetTripleSys = try container.decode(String.self, forKey: .llvmTargetTripleSys)
        let rawEnvironment = try container.decodeIfPresent(String.self, forKey: .llvmTargetTripleEnvironment)
        llvmTargetTripleEnvironment = rawEnvironment?.isEmpty == true ? nil : rawEnvironment
        defaultDeploymentTarget = try container.decode(String.self, forKey: .defaultDeploymentTarget)
    }
}

/// Target spellings derived from one SDK target definition.
struct SDKTargetTriples {
    let swift: String
    let tbd: String
}

/// Values shared by every relinking operation together with SDK- and architecture-specific values.
public struct ScopedValues: Sendable {
    /// Values applied to every SDK.
    public let base: [String]
    /// Values added only when relinking a slice built with the dictionary key's SDK.
    public let sdkSpecific: [String: [String]]
    /// Values added only when relinking the dictionary key's architecture.
    public let architectureSpecific: [String: [String]]

    /// Creates values that can be shared by all slices or restricted to individual SDKs and architectures.
    public init(
        base: [String] = [],
        sdkSpecific: [String: [String]] = [:],
        architectureSpecific: [String: [String]] = [:],
    ) {
        self.base = base
        self.sdkSpecific = sdkSpecific
        self.architectureSpecific = architectureSpecific
    }

    /// Returns the shared and SDK-specific values followed by the values configured for `architecture`.
    public func values(for sdk: String, architecture: String) -> [String] {
        base + sdkSpecific[sdk, default: []] + architectureSpecific[architecture, default: []]
    }
}

/// Linking options received from the CLI.
public struct RelinkOptions: Sendable {
    /// Raw linker arguments.
    public let linkerArgs: ScopedValues
    /// Auto-linked dependency names to ignore.
    public let ignoredAutolinkDependencies: ScopedValues
    /// Archive object name patterns to exclude before linking.
    public let excludedObjectNamePatterns: ScopedValues

    /// Creates relinking options.
    public init(
        linkerArgs: ScopedValues = ScopedValues(),
        ignoredAutolinkDependencies: ScopedValues = ScopedValues(),
        excludedObjectNamePatterns: ScopedValues = ScopedValues(),
    ) {
        self.linkerArgs = linkerArgs
        self.ignoredAutolinkDependencies = ignoredAutolinkDependencies
        self.excludedObjectNamePatterns = excludedObjectNamePatterns
    }
}
