import DylibForgeArchive
import DylibForgeCore

/// Raw SDK-grouped arguments accepted by the XCFramework converter.
///
/// In each collection, an SDK name or `any` begins a group. The following values belong to that group until the
/// next SDK name. The `any` group is applied to every rebuilt slice.
public struct XCFrameworkSDKArguments: Sendable {
    /// Raw linker arguments grouped by SDK.
    public let linkerArgs: [String]

    /// Autolink dependency names to ignore, grouped by SDK.
    public let ignoredAutolinkDependencies: [String]

    /// Archive object name patterns to exclude, grouped by SDK.
    public let excludedObjectNamePatterns: [String]

    /// Creates raw SDK-grouped converter arguments.
    public init(
        linkerArgs: [String] = [],
        ignoredAutolinkDependencies: [String] = [],
        excludedObjectNamePatterns: [String] = [],
    ) {
        self.linkerArgs = linkerArgs
        self.ignoredAutolinkDependencies = ignoredAutolinkDependencies
        self.excludedObjectNamePatterns = excludedObjectNamePatterns
    }
}

/// Converts static library artifacts inside an XCFramework into dynamic libraries.
public enum DylibForgeXCFramework {
    /// Copies an XCFramework, relinks static artifacts, and removes code signatures from the copy.
    ///
    /// Static `.a` entries become sibling `.dylib` files and their `LibraryPath` values are updated in the root
    /// `Info.plist`. Static framework binaries are rebuilt in place. The supplied linker options are applied to
    /// every rebuilt artifact. Values from `sdkArguments` are applied only to matching artifacts, while each
    /// artifact's SDK and install name are derived from its own metadata.
    public static func run(
        inputPath: String,
        outputPath: String,
        sdkArguments: XCFrameworkSDKArguments = XCFrameworkSDKArguments(),
        xcframeworkDependencies: [String],
        xcodePath: String? = nil,
    ) async throws {
        // Keep file access shared by the converter and artifact relinker, mirroring the core tool environment.
        let files = XCFrameworkFiles()
        let dependencyResolver = try XCFrameworkDependencyResolver(paths: xcframeworkDependencies, files: files)
        let developerDirectory = try await XcodePathProvider().developerDirectory(for: xcodePath)
        let sdkNameResolver = XCFrameworkSDKNameResolver(
            commandExecutor: DeveloperCommandExecutor(developerDirectory: developerDirectory),
        )
        let sdkOptions = try await sdkNameResolver.options(
            linkerArgs: sdkArguments.linkerArgs,
            ignoredAutolinkDependencies: sdkArguments.ignoredAutolinkDependencies,
            excludedObjectNamePatterns: sdkArguments.excludedObjectNamePatterns,
        )
        let artifactRelinker = XCFrameworkArtifactRelinker(
            files: files,
            dylibForge: DylibForge.self,
            dependencyResolver: dependencyResolver,
            sdkNameResolver: sdkNameResolver,
            xcodePath: xcodePath,
        )
        let converter = XCFrameworkConverter(
            files: files,
            artifactRelinker: artifactRelinker,
        )

        try await converter.run(
            inputPath: inputPath,
            outputPath: outputPath,
            relinkOptions: RelinkOptions(
                linkerArgs: scopedValues(sdkOptions.linkerArgs),
                ignoredAutolinkDependencies: scopedValues(sdkOptions.ignoredAutolinkDependencies),
                excludedObjectNamePatterns: scopedValues(sdkOptions.excludedObjectNamePatterns),
            ),
        )
    }
}

private extension DylibForgeXCFramework {
    static func scopedValues(_ sdkArguments: [String: [String]]) -> ScopedValues {
        var sdkArguments = sdkArguments
        return ScopedValues(
            base: sdkArguments.removeValue(forKey: "any") ?? [],
            sdkSpecific: sdkArguments,
        )
    }
}
