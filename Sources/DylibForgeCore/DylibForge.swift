import Foundation

public enum DylibForge {
    @discardableResult
    public static func run(
        inputPath: String,
        outputPath: String,
        sdk: String,
        installName: String,
        relinkOptions: RelinkOptions,
    ) async throws -> RelinkResult {
        let environment = ToolEnvironment()
        let machoEditor = MachOEditor()
        let archiveExtractor = ArchiveExtractor(
            environment: environment,
            machoEditor: machoEditor,
        )
        let clangLinker = ClangLinker(
            environment: environment,
            machoEditor: machoEditor,
        )
        let relinker = ArchiveRelinker(
            environment: environment,
            archiveExtractor: archiveExtractor,
            clangLinker: clangLinker,
            machoEditor: machoEditor,
        )

        return try await relinker.run(
            inputPath: inputPath,
            outputPath: outputPath,
            sdk: sdk,
            installName: installName,
            overrides: relinkOptions,
        )
    }
}
