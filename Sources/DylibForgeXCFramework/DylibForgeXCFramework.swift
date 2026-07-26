import DylibForgeCore

/// Converts static library artifacts inside an XCFramework into dynamic libraries.
public enum DylibForgeXCFramework {
    /// Copies an XCFramework, relinks static artifacts, and removes code signatures from the copy.
    ///
    /// Static `.a` entries become sibling `.dylib` files and their `LibraryPath` values are updated in the root
    /// `Info.plist`. Static framework binaries are rebuilt in place. The supplied linker options are applied to
    /// every rebuilt artifact, while each artifact's SDK and install name are derived from its own metadata.
    public static func run(
        inputPath: String,
        outputPath: String,
        relinkOptions: RelinkOptions,
    ) async throws {
        // Keep file access shared by the converter and artifact relinker, mirroring the core tool environment.
        let files = XCFrameworkFiles()
        let artifactRelinker = XCFrameworkArtifactRelinker(
            files: files,
            dylibForge: DylibForge.self,
        )
        let converter = XCFrameworkConverter(
            files: files,
            artifactRelinker: artifactRelinker,
        )

        try await converter.run(
            inputPath: inputPath,
            outputPath: outputPath,
            relinkOptions: relinkOptions,
        )
    }
}
