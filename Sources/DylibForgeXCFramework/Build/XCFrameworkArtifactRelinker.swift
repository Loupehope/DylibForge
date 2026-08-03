import DylibForgeArchive
import Foundation

/// Rebuilds one XCFramework artifact using the core archive relinker.
final class XCFrameworkArtifactRelinker {
    private let files: XCFrameworkFiles
    private let dylibForge: DylibForge.Type
    private let dependencyResolver: XCFrameworkDependencyResolver
    private let sdkNameResolver: XCFrameworkSDKNameResolver
    private let xcodePath: String?

    /// Wires artifact rebuilding around shared file access and the core relinker entry point.
    init(
        files: XCFrameworkFiles,
        dylibForge: DylibForge.Type,
        dependencyResolver: XCFrameworkDependencyResolver,
        sdkNameResolver: XCFrameworkSDKNameResolver,
        xcodePath: String?,
    ) {
        self.files = files
        self.dylibForge = dylibForge
        self.dependencyResolver = dependencyResolver
        self.sdkNameResolver = sdkNameResolver
        self.xcodePath = xcodePath
    }

    /// Rebuilds one static archive or framework entry.
    func relink(
        _ library: inout XCFrameworkLibrary,
        in xcframeworkURL: URL,
        relinkOptions: RelinkOptions,
    ) async throws {
        let artifactURL = try library.artifactURL(in: xcframeworkURL)
        let dependencyArgs = try dependencyResolver.linkerArgs(for: library)
        let options = RelinkOptions(
            linkerArgs: ScopedValues(
                base: relinkOptions.linkerArgs.base,
                sdkSpecific: relinkOptions.linkerArgs.sdkSpecific,
                architectureSpecific: relinkOptions.linkerArgs.architectureSpecific.merging(dependencyArgs) { $0 + $1 },
            ),
            ignoredAutolinkDependencies: relinkOptions.ignoredAutolinkDependencies,
            excludedObjectNamePatterns: relinkOptions.excludedObjectNamePatterns,
        )

        switch library.artifactKind {
        case .staticArchive:
            try await relinkArchive(
                at: artifactURL,
                library: &library,
                relinkOptions: options,
            )
        case .framework:
            try await relinkFramework(
                at: artifactURL,
                library: &library,
                relinkOptions: options,
            )
        case .other:
            return
        }
    }
}

private extension XCFrameworkArtifactRelinker {
    /// Converts a static archive to a sibling dylib, then updates its manifest entry.
    func relinkArchive(
        at archiveURL: URL,
        library: inout XCFrameworkLibrary,
        relinkOptions: RelinkOptions,
    ) async throws {
        guard files.fileExists(at: archiveURL) else {
            throw XCFrameworkError.message("Static archive does not exist: \(archiveURL.path)")
        }

        let dylibURL = archiveURL.deletingPathExtension().appendingPathExtension("dylib")

        let targetSDK = try sdkNameResolver.sdk(for: library)
        let result = try await dylibForge.run(
            inputPath: archiveURL.path,
            outputPath: dylibURL.path,
            sdk: targetSDK,
            installName: "@rpath/\(dylibURL.lastPathComponent)",
            relinkOptions: relinkOptions,
            xcodePath: xcodePath,
        )
        // The copied archive is no longer referenced after the manifest points to the new dylib.
        try files.removeItem(at: archiveURL)
        library.replaceStaticArchive(with: dylibURL)
        library.replaceSupportedArchitectures(with: result.linkedArchitectures)
    }

    /// Rebuilds a framework executable in place using its bundle metadata for the install name and SDK.
    func relinkFramework(
        at frameworkURL: URL,
        library: inout XCFrameworkLibrary,
        relinkOptions: RelinkOptions,
    ) async throws {
        let bundleInfo = try files.readBundleInfo(at: frameworkURL)
        let binaryURL = frameworkURL
            .appendingPathComponent(bundleInfo.executableName)
            .resolvingSymlinksInPath()

        let targetSDK = try sdkNameResolver.sdk(for: library, bundleInfo: bundleInfo)
        let result = try await dylibForge.run(
            inputPath: binaryURL.path,
            outputPath: binaryURL.path,
            sdk: targetSDK,
            installName: "@rpath/\(frameworkURL.lastPathComponent)/\(bundleInfo.executableName)",
            relinkOptions: relinkOptions,
            xcodePath: xcodePath,
        )
        library.replaceSupportedArchitectures(with: result.linkedArchitectures)
    }
}
