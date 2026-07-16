import Foundation

/// Facade over Mach-O parsing that hides low-level parsers behind the builder-facing API.
final class MachOEditor {
    private let symbolInspector: MachOSymbolInspector
    private let autolinkParser: MachOAutolinkParser

    /// Wires the Mach-O parser dependency graph; parameters support tests and explicit component substitution.
    init() {
        symbolInspector = MachOSymbolInspector()
        autolinkParser = MachOAutolinkParser()
    }

    /// Returns `true` when the file is already a dynamic library.
    func isDynamicLibrary(_ data: Data) -> Bool {
        MachOReader(data: data).fileType == MachOConstants.mhDylib
    }

    /// Returns the `Mach-O` file type.
    func fileType(of data: Data) -> UInt32? {
        MachOReader(data: data).fileType
    }

    /// Makes private ObjC runtime symbols external so the final dynamic library can expose them.
    func patchObjCSymbolVisibility(in buffer: inout Data) {
        symbolInspector.patchObjCSymbolVisibility(in: &buffer)
    }

    /// Returns external native definitions for object-level deduplication of repeated native members.
    func externalNativeDefinitionNames(in data: Data) -> Set<String> {
        symbolInspector.externalNativeDefinitionNames(in: data)
    }

    /// Makes selected external native definitions local inside the object file.
    func makeExternalNativeDefinitionsLocal(
        in buffer: inout Data,
        named targetNames: Set<String>,
    ) {
        symbolInspector.makeExternalNativeDefinitionsLocal(
            in: &buffer,
            named: targetNames,
        )
    }

    /// Parses `LC_LINKER_OPTION` as an array of linker tokens.
    func parseLinkerOptions(in data: Data) -> [String] {
        autolinkParser.parseLinkerOptions(in: data)
    }

    /// Parses the Swift autolink section `__swift1_autolink_entries`.
    func parseSwiftAutolinkEntries(in data: Data) -> [String] {
        autolinkParser.parseSwiftAutolinkEntries(in: data)
    }
}
