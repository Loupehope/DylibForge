import DylibForgeCore
import Foundation
import Logging

/// Orchestrates copying an XCFramework and rebuilding its static artifacts.
final class XCFrameworkConverter {
    private let logger: Logger
    private let files: XCFrameworkFiles
    private let artifactRelinker: XCFrameworkArtifactRelinker

    /// Wires the orchestration layer around file access and single-artifact rebuilding.
    init(
        files: XCFrameworkFiles,
        artifactRelinker: XCFrameworkArtifactRelinker,
        logger: Logger = Logger(label: "dylib-forge.xcframework"),
    ) {
        self.files = files
        self.artifactRelinker = artifactRelinker
        self.logger = logger
    }

    /// Produces a fully copied, unsigned XCFramework with every supported static artifact rebuilt.
    func run(inputPath: String, outputPath: String, relinkOptions: RelinkOptions) async throws {
        let inputURL = URL(fileURLWithPath: inputPath).standardizedFileURL
        let outputURL = URL(fileURLWithPath: outputPath).standardizedFileURL
        try validateInput(at: inputURL)

        let conversionURL = temporaryOutputURL(for: outputURL)
        defer { try? files.removeItemIfExists(at: conversionURL) }

        logger.notice("Input XCFramework: \(inputURL.path)")
        try files.copyItem(at: inputURL, to: conversionURL)

        let manifestURL = conversionURL.appendingPathComponent("Info.plist")
        var manifest = try files.readManifest(at: manifestURL)
        try removeUnsupportedArtifacts(from: &manifest, in: conversionURL)
        // Mutate one manifest entry at a time so an archive replacement is reflected before serialization.
        for index in manifest.availableLibraries.indices {
            try await artifactRelinker.relink(
                &manifest.availableLibraries[index],
                in: conversionURL,
                relinkOptions: relinkOptions,
            )
        }

        try files.writeManifest(manifest, to: manifestURL)
        try files.removeCodeSignatures(from: conversionURL, libraries: manifest.availableLibraries)
        try files.replaceOutput(at: outputURL, with: conversionURL)
        logger.notice("Output XCFramework: \(outputURL.path)")
    }
}

private extension XCFrameworkConverter {
    /// Creates a sibling temporary directory so the output is changed only after a successful conversion.
    func temporaryOutputURL(for outputURL: URL) -> URL {
        outputURL
            .deletingLastPathComponent()
            .appendingPathComponent(".\(outputURL.lastPathComponent).dylib-forge-\(UUID().uuidString)")
    }

    /// Verifies that the input exists and has the expected XCFramework directory shape.
    func validateInput(at inputURL: URL) throws {
        guard files.fileExists(at: inputURL) else {
            throw XCFrameworkError.message("Path does not exist: \(inputURL.path)")
        }
        guard inputURL.pathExtension == "xcframework", files.isDirectory(at: inputURL) else {
            throw XCFrameworkError.message("Expected an XCFramework directory: \(inputURL.path)")
        }
    }

    /// Removes Mac Catalyst slices because they are intentionally unsupported by this converter.
    func removeUnsupportedArtifacts(from manifest: inout XCFrameworkManifest, in xcframeworkURL: URL) throws {
        let unsupportedLibraries = manifest.availableLibraries.filter { $0.supportedPlatformVariant == "maccatalyst" }
        guard !unsupportedLibraries.isEmpty else {
            return
        }

        let unsupportedIdentifiers = Set(unsupportedLibraries.map(\.identifier))
        let supportedIdentifiers = Set(
            manifest.availableLibraries
                .filter { $0.supportedPlatformVariant != "maccatalyst" }
                .map(\.identifier),
        )
        for identifier in unsupportedIdentifiers.subtracting(supportedIdentifiers) {
            let artifactDirectory = xcframeworkURL.appendingPathComponent(identifier, isDirectory: true)
            try files.removeItemIfExists(at: artifactDirectory)
        }

        manifest.availableLibraries.removeAll { $0.supportedPlatformVariant == "maccatalyst" }
        logger.warning("Removed \(unsupportedLibraries.count) unsupported Mac Catalyst artifact(s)")
    }
}
