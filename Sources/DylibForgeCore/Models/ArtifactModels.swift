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

/// Resolved inputs for linking one architecture slice.
struct DynamicSliceLinkContext {
    let sdk: String
    let sdkPath: String
    let swiftTargetTriple: String?
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

/// System command output.
struct CommandResult {
    let stdout: String
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

/// Linking options received from the CLI.
public struct RelinkOptions: Sendable {
    public let linkerArgs: [String]
    public let ignoredAutolinkDependencies: [String]
    public let installName: String?
    public let excludedObjectNamePatterns: [String]

    public init(
        linkerArgs: [String],
        ignoredAutolinkDependencies: [String] = [],
        installName: String? = nil,
        excludedObjectNamePatterns: [String] = [],
    ) {
        self.linkerArgs = linkerArgs
        self.ignoredAutolinkDependencies = ignoredAutolinkDependencies
        self.installName = installName
        self.excludedObjectNamePatterns = excludedObjectNamePatterns
    }
}
