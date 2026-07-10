import Foundation

public enum DylibForge {
    public static func run(
        inputPath: String,
        outputPath: String,
        sdk: String,
        relinkOptions: RelinkOptions,
    ) async throws {
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

        try await relinker.run(
            inputPath: inputPath,
            outputPath: outputPath,
            sdk: sdk,
            overrides: relinkOptions,
        )
    }
}
