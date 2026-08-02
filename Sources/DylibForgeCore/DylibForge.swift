import DylibForgeSubprocess
import Foundation

public enum DylibForge {
    @discardableResult
    public static func run(
        inputPath: String,
        outputPath: String,
        sdk: String,
        installName: String,
        relinkOptions: RelinkOptions,
        xcodePath: String? = nil,
    ) async throws -> RelinkResult {
        let developerDirectory = try await XcodePathProvider().developerDirectory(for: xcodePath)
        let environment = ToolEnvironment(
            shell: DeveloperCommandExecutor(developerDirectory: developerDirectory),
        )
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
