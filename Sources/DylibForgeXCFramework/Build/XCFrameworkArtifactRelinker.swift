import DylibForgeCore
import Foundation
import Logging

/// Rebuilds one XCFramework artifact using the core archive relinker.
final class XCFrameworkArtifactRelinker {
    private let logger = Logger(label: "dylib-forge.xcframework")
    private let files: XCFrameworkFiles
    private let dylibForge: DylibForge.Type

    /// Wires artifact rebuilding around shared file access and the core relinker entry point.
    init(files: XCFrameworkFiles, dylibForge: DylibForge.Type) {
        self.files = files
        self.dylibForge = dylibForge
    }

    /// Rebuilds one static archive or framework entry, leaving unsupported artifact forms untouched.
    func relink(
        _ library: inout XCFrameworkLibrary,
        in xcframeworkURL: URL,
        relinkOptions: RelinkOptions,
    ) async throws {
        let artifactURL = library.artifactURL(in: xcframeworkURL)
        switch library.artifactKind {
        case .staticArchive:
            try await relinkArchive(
                at: artifactURL,
                library: &library,
                relinkOptions: relinkOptions,
            )
        case .framework:
            try await relinkFramework(
                at: artifactURL,
                library: &library,
                relinkOptions: relinkOptions,
            )
        case .other:
            logger.info("Keeping non-static artifact unchanged: \(artifactURL.path)")
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

        let result = try await dylibForge.run(
            inputPath: archiveURL.path,
            outputPath: dylibURL.path,
            sdk: sdk(for: library),
            relinkOptions: resolvedRelinkOptions(
                from: relinkOptions,
                installName: "@rpath/\(dylibURL.lastPathComponent)",
                library: library,
            ),
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
        let binaryURL = frameworkURL.appendingPathComponent(bundleInfo.executableName)

        let result = try await dylibForge.run(
            inputPath: binaryURL.path,
            outputPath: binaryURL.path,
            sdk: sdk(for: library, bundleInfo: bundleInfo),
            relinkOptions: resolvedRelinkOptions(
                from: relinkOptions,
                installName: "@rpath/\(frameworkURL.lastPathComponent)/\(bundleInfo.executableName)",
                library: library,
            ),
        )
        library.replaceSupportedArchitectures(with: result.linkedArchitectures)
    }

    /// Retains user-provided linker controls while supplying metadata that must be artifact-specific.
    func resolvedRelinkOptions(
        from baseOptions: RelinkOptions,
        installName: String,
        library _: XCFrameworkLibrary,
    ) -> RelinkOptions {
        RelinkOptions(
            linkerArgs: baseOptions.linkerArgs,
            ignoredAutolinkDependencies: baseOptions.ignoredAutolinkDependencies,
            installName: installName,
            excludedObjectNamePatterns: baseOptions.excludedObjectNamePatterns,
        )
    }

    /// Selects the SDK for an artifact, preferring a framework bundle's explicit Xcode platform name.
    func sdk(for library: XCFrameworkLibrary, bundleInfo: XCFrameworkBundleInfo? = nil) throws -> String {
        if let platformName = bundleInfo?.platformName, !platformName.isEmpty {
            return platformName
        }

        guard let platform = library.supportedPlatform else {
            throw XCFrameworkError.message("AvailableLibraries item has no SupportedPlatform")
        }

        switch (platform, library.supportedPlatformVariant) {
        case ("ios", "simulator"):
            return "iphonesimulator"
        case ("ios", _):
            return "iphoneos"
        case ("tvos", "simulator"):
            return "appletvsimulator"
        case ("tvos", _):
            return "appletvos"
        case ("watchos", "simulator"):
            return "watchsimulator"
        case ("watchos", _):
            return "watchos"
        case ("xros", "simulator"), ("visionos", "simulator"):
            return "xrsimulator"
        case ("xros", _), ("visionos", _):
            return "xros"
        case ("macos", _):
            return "macosx"
        default:
            let variant = library.supportedPlatformVariant.map { " (\($0))" } ?? ""
            throw XCFrameworkError.message("Unsupported XCFramework platform: \(platform)\(variant)")
        }
    }
}
