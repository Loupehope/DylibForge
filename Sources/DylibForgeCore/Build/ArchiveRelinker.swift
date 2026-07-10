import Foundation
import Logging

/// Orchestrates relinking a static archive into a dynamic Mach-O binary.
final class ArchiveRelinker {
    private let logger = Logger(label: "dylib-forge.build")
    private let environment: ToolEnvironment
    private let archiveExtractor: ArchiveExtractor
    private let clangLinker: ClangLinker
    private let machoEditor: MachOEditor

    init(
        environment: ToolEnvironment,
        archiveExtractor: ArchiveExtractor,
        clangLinker: ClangLinker,
        machoEditor: MachOEditor,
    ) {
        self.environment = environment
        self.archiveExtractor = archiveExtractor
        self.clangLinker = clangLinker
        self.machoEditor = machoEditor
    }

    /// Main CLI entry point.
    func run(inputPath: String, outputPath: String, sdk: String, overrides: RelinkOptions) async throws {
        let inputURL = URL(fileURLWithPath: inputPath).standardizedFileURL
        let destination = URL(fileURLWithPath: outputPath).standardizedFileURL
        let target = try resolveArchive(at: inputURL, sdk: sdk, outputURL: destination)
        let outputBinaryName = target.outputBinaryName
        let installName = try resolvedInstallName(overrides.installName)

        try await relinkArchive(
            target: target,
            outputBinaryName: outputBinaryName,
            installName: installName,
            overrides: overrides,
            outputFileURL: destination,
        )
    }
}

private extension ArchiveRelinker {
    /// Rebuilds a single archive into a dynamic binary.
    func relinkArchive(
        target: RelinkTarget,
        outputBinaryName: String,
        installName: String,
        overrides: RelinkOptions,
        outputFileURL: URL,
    ) async throws {
        logger.notice("Build started")
        logger.info("Input archive: \(target.inputURL.path)")

        // Keep all intermediate slices and unpacked objects in one disposable workspace.
        let temporaryRoot = environment.files.temporaryDirectory.appendingPathComponent("dylib_forge_\(UUID().uuidString)")
        try environment.files.createDirectory(at: temporaryRoot)
        defer { try? environment.files.removeItem(at: temporaryRoot) }

        // Detect which architecture slices should be rebuilt.
        let slices = try await clangLinker.detectArchitectures(in: target.binaryURL)

        // Build or copy one dynamic slice per architecture.
        var dynamicSlices: [URL] = []
        for architecture in slices.architectures {
            let dynamicSliceURL = try await buildArchitectureSlice(
                target: target,
                architecture: architecture,
                isUniversalInput: slices.isUniversal,
                temporaryRoot: temporaryRoot,
                installName: installName,
                overrides: overrides,
            )
            dynamicSlices.append(dynamicSliceURL)
        }

        // Merge rebuilt slices back into the final binary shape.
        let mergedBinaryURL = temporaryRoot.appendingPathComponent(outputBinaryName)
        if dynamicSlices.count == 1, let onlySlice = dynamicSlices.first {
            try environment.files.copyItem(at: onlySlice, to: mergedBinaryURL)
        } else {
            _ = try await environment.shell.run(
                arguments: ["lipo", "-create"] + dynamicSlices.map(\.path) + ["-output", mergedBinaryURL.path],
            )
        }

        // Replace the requested output atomically from the completed temporary binary.
        try environment.files.createDirectory(at: outputFileURL.deletingLastPathComponent())
        if environment.files.fileExists(atPath: outputFileURL.path) {
            try environment.files.removeItem(at: outputFileURL)
        }
        try environment.files.copyItem(at: mergedBinaryURL, to: outputFileURL)
        logger.notice("Build finished: \(outputFileURL.path)")
    }

    /// Produces a dynamic dylib for one architecture slice.
    func buildArchitectureSlice(
        target: RelinkTarget,
        architecture: String,
        isUniversalInput: Bool,
        temporaryRoot: URL,
        installName: String,
        overrides: RelinkOptions,
    ) async throws -> URL {
        let thinArchiveURL = temporaryRoot.appendingPathComponent("\(architecture).a")
        let objectsDirectoryURL = temporaryRoot.appendingPathComponent("\(architecture)_objects", isDirectory: true)
        let dynamicSliceURL = temporaryRoot.appendingPathComponent("\(architecture).dylib")

        // Fat archives must be thinned before archive extraction and linking.
        if isUniversalInput {
            _ = try await environment.shell.run("lipo", target.binaryURL.path, "-thin", architecture, "-output", thinArchiveURL.path)
        } else {
            try environment.files.copyItem(at: target.binaryURL, to: thinArchiveURL)
        }

        // Already-dynamic inputs do not need archive extraction or relinking.
        let thinBinary = try environment.files.readFile(at: thinArchiveURL)
        if machoEditor.isDynamicLibrary(thinBinary) {
            try environment.files.copyItem(at: thinArchiveURL, to: dynamicSliceURL)
            return dynamicSliceURL
        }

        // Extract native objects and combine auto-detected autolink directives with CLI overrides.
        let extractedObjects = try archiveExtractor.extractObjectFiles(
            from: thinArchiveURL,
            to: objectsDirectoryURL,
            excludedObjectNamePatterns: overrides.excludedObjectNamePatterns,
        )
        let detectedAutolinkDirectives = try clangLinker.extractAutolinkDirectives(from: extractedObjects.objectFiles)
        let finalAutolinkDirectives = clangLinker.mergeAutolinkDirectives(auto: detectedAutolinkDirectives, cli: overrides)

        let linkContext = try await clangLinker.makeDynamicSliceLinkContext(
            sdk: target.sdk,
            architecture: architecture,
            objectFiles: extractedObjects.objectFiles,
            outputFile: dynamicSliceURL,
            installName: installName,
            autolinkDirectives: finalAutolinkDirectives,
            linkerArgs: overrides.linkerArgs,
        )

        // Link the object files into a dynamic slice for this architecture.
        try await clangLinker.buildDynamicSlice(context: linkContext)

        return dynamicSliceURL
    }

    /// Validates and normalizes the install name used by the produced dylib.
    func resolvedInstallName(_ explicitInstallName: String?) throws -> String {
        guard let explicitInstallName else {
            throw DylibForgeError.message("Missing required --install-name. For a framework binary use something like @rpath/Foo.framework/Foo")
        }

        let trimmedInstallName = explicitInstallName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedInstallName.isEmpty else {
            throw DylibForgeError.message("Install name cannot be empty")
        }
        return trimmedInstallName
    }

    /// Validates the input path and creates the internal artifact description.
    func resolveArchive(at inputURL: URL, sdk: String, outputURL: URL) throws -> RelinkTarget {
        guard environment.files.fileExists(atPath: inputURL.path) else {
            throw DylibForgeError.message("Path does not exist: \(inputURL.path)")
        }

        if environment.files.isDirectory(atPath: inputURL.path) {
            throw DylibForgeError.message("Expected a static archive file, but received a directory: \(inputURL.path)")
        }

        let outputBinaryName = outputURL.deletingPathExtension().lastPathComponent

        return RelinkTarget(
            inputURL: inputURL,
            binaryURL: inputURL,
            outputBinaryName: outputBinaryName,
            sdk: sdk,
        )
    }
}
