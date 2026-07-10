import Foundation

/// Extracts Mach-O object files from an `ar` archive.
final class ArchiveExtractor {
    private let environment: ToolEnvironment
    private let machoEditor: MachOEditor
    private let archiveReader: ArArchiveReader

    /// Wires archive extraction around the shared Mach-O editor.
    init(environment: ToolEnvironment, machoEditor: MachOEditor) {
        self.environment = environment
        self.machoEditor = machoEditor
        archiveReader = ArArchiveReader()
    }

    /// Unpacks object files and immediately fixes ObjC symbol visibility.
    func extractObjectFiles(
        from archiveURL: URL,
        to outputDirectoryURL: URL,
        excludedObjectNamePatterns: [String],
    ) throws -> ExtractedObjects {
        let archiveData = try environment.files.readFile(at: archiveURL)
        guard archiveReader.isArchive(archiveData) else {
            throw DylibForgeError.message("Input is not a static ar archive: \(archiveURL.path)")
        }

        try environment.files.createDirectory(at: outputDirectoryURL)
        let duplicateTracker = NativeObjectDuplicateTracker(machoEditor: machoEditor)

        var extractedObjectFiles: [URL] = []
        for member in try archiveReader.members(in: archiveData) {
            let outputURL = try process(
                member: member,
                outputDirectoryURL: outputDirectoryURL,
                excludedObjectNamePatterns: excludedObjectNamePatterns,
                outputIndex: extractedObjectFiles.count + 1,
                duplicateTracker: duplicateTracker,
            )
            if let outputURL {
                extractedObjectFiles.append(outputURL)
            }
        }

        guard !extractedObjectFiles.isEmpty else {
            throw DylibForgeError.message("No object files were extracted from archive: \(archiveURL.path)")
        }

        return ExtractedObjects(objectFiles: extractedObjectFiles)
    }
}

private extension ArchiveExtractor {
    /// Processes one archive member: filters, deduplicates, patches, and writes the object file.
    func process(
        member: ArArchiveMember,
        outputDirectoryURL: URL,
        excludedObjectNamePatterns: [String],
        outputIndex: Int,
        duplicateTracker: NativeObjectDuplicateTracker,
    ) throws -> URL? {
        guard shouldExtract(member) else {
            return nil
        }

        if shouldSkip(member, excludedObjectNamePatterns: excludedObjectNamePatterns) {
            return nil
        }

        // Drop only byte-identical objects and prepare duplicate definitions for localization.
        let duplicateInfo = duplicateTracker.inspect(member.payload)
        if duplicateInfo.shouldSkipObject {
            return nil
        }

        // Patch symbol visibility and localize duplicate definitions before writing the object file.
        let outputURL = outputDirectoryURL.appendingPathComponent(outputFileName(for: member.baseName, index: outputIndex))
        var patchedBuffer = member.payload
        machoEditor.patchObjCSymbolVisibility(in: &patchedBuffer)
        machoEditor.makeExternalNativeDefinitionsLocal(
            in: &patchedBuffer,
            named: duplicateInfo.duplicateDefinitions,
        )
        try environment.files.write(patchedBuffer, to: outputURL)

        // Record only definitions from objects that made it into the final link set.
        duplicateTracker.recordIncludedDefinitions(duplicateInfo.definitions)
        return outputURL
    }

    /// Checks whether the member is a Mach-O object rather than an archive bookkeeping table.
    func shouldExtract(_ member: ArArchiveMember) -> Bool {
        !member.isArchiveIndex && machoEditor.fileType(of: member.payload) == 0x1
    }

    /// Applies explicit user-defined object-file exclusion rules.
    func shouldSkip(_ member: ArArchiveMember, excludedObjectNamePatterns: [String]) -> Bool {
        excludedObjectNamePatterns
            .filter { !$0.isEmpty }
            .contains { member.baseName.contains($0) }
    }

    /// Returns the output object-file name with a stable numeric prefix.
    func outputFileName(for baseName: String, index: Int) -> String {
        let normalizedBaseName = baseName.hasSuffix(".o") ? baseName : "\(baseName).o"
        return String(format: "%05d_%@", index, normalizedBaseName)
    }
}
