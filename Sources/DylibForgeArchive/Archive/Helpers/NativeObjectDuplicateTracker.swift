import CryptoKit
import Foundation

/// Tracks repeated native object files and overlapping external native definitions.
final class NativeObjectDuplicateTracker {
    private let machoEditor: MachOEditor
    private var seenObjectPayloadDigests = Set<String>()
    private var seenDefinitions = Set<String>()

    /// Accepts the Mach-O inspector used to read native definitions.
    init(machoEditor: MachOEditor) {
        self.machoEditor = machoEditor
    }

    /// Returns the object-file decision: skip byte-identical objects or privatize selected symbols.
    func inspect(_ payload: Data, digest: String) -> NativeDuplicateInfo {
        let definitions = machoEditor.externalNativeDefinitionNames(in: payload)
        let duplicateDefinitions = definitions.intersection(seenDefinitions)
        let shouldSkipObject = isByteIdenticalDuplicate(digest)
        return NativeDuplicateInfo(
            definitions: definitions,
            duplicateDefinitions: duplicateDefinitions,
            shouldSkipObject: shouldSkipObject,
        )
    }

    /// Records definitions only for object files that were actually included in the final link.
    func recordIncludedDefinitions(_ definitions: Set<String>) {
        seenDefinitions.formUnion(definitions)
    }
}

private extension NativeObjectDuplicateTracker {
    /// Treats an object as a full duplicate only when the original member bytes are identical.
    func isByteIdenticalDuplicate(_ digest: String) -> Bool {
        let inserted = seenObjectPayloadDigests.insert(digest).inserted
        return !inserted
    }
}

/// Result of native-duplicate analysis for an object file.
struct NativeDuplicateInfo {
    let definitions: Set<String>
    let duplicateDefinitions: Set<String>
    let shouldSkipObject: Bool
}
