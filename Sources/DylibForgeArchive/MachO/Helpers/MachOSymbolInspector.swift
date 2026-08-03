import Foundation

/// Parses and mutates the symbol table of Mach-O object files.
final class MachOSymbolInspector {
    /// Makes private ObjC symbols external so the final dynamic library can expose them.
    func patchObjCSymbolVisibility(in buffer: inout Data) {
        let reader = makeReader(for: buffer)
        guard reader.isObject,
              let symbolTable = reader.symbolTable()
        else {
            return
        }
        let sections = reader.sections()

        for symbolOffset in reader.symbolOffsets(in: symbolTable) {
            patchObjCSymbolIfNeeded(
                in: &buffer,
                reader: reader,
                symbolOffset: symbolOffset,
                sections: sections,
            )
        }
    }

    /// Returns external native definitions for object-level deduplication of repeated native members.
    func externalNativeDefinitionNames(in data: Data) -> Set<String> {
        let reader = makeReader(for: data)
        guard reader.isObject,
              let symbolTable = reader.symbolTable()
        else {
            return []
        }
        let sections = reader.sections()

        var names = Set<String>()
        for symbolOffset in reader.symbolOffsets(in: symbolTable) {
            guard let name = externalNativeDefinitionName(
                reader: reader,
                symbolOffset: symbolOffset,
                symbolTable: symbolTable,
                sections: sections,
            ) else {
                continue
            }

            names.insert(name)
        }

        return names
    }

    /// Makes selected external native definitions local inside the object file.
    func makeExternalNativeDefinitionsLocal(
        in buffer: inout Data,
        named targetNames: Set<String>,
    ) {
        let reader = makeReader(for: buffer)
        guard !targetNames.isEmpty,
              reader.isObject,
              let symbolTable = reader.symbolTable()
        else {
            return
        }
        let sections = reader.sections()

        for symbolOffset in reader.symbolOffsets(in: symbolTable) {
            guard let name = externalNativeDefinitionName(
                reader: reader,
                symbolOffset: symbolOffset,
                symbolTable: symbolTable,
                sections: sections,
            ), targetNames.contains(name) else {
                continue
            }

            let typeOffset = symbolOffset + MachOSymbolLayout.typeOffset
            buffer[typeOffset] = buffer[typeOffset] & ~MachOConstants.nExt & ~MachOConstants.nPext
        }
    }
}

private extension MachOSymbolInspector {
    /// Creates a reader with the same dependencies as the current symbol inspector.
    func makeReader(for data: Data) -> MachOReader {
        MachOReader(data: data)
    }

    /// Checks one `nlist` entry and exports the ObjC runtime symbol if it was private external.
    func patchObjCSymbolIfNeeded(
        in buffer: inout Data,
        reader: MachOReader,
        symbolOffset: Int,
        sections: [MachOSection],
    ) {
        let typeOffset = symbolOffset + MachOSymbolLayout.typeOffset
        guard typeOffset < buffer.count else {
            return
        }

        let symbolType = buffer[typeOffset]
        guard (symbolType & MachOConstants.nStabMask) == 0,
              (symbolType & MachOConstants.nPext) != 0,
              (symbolType & MachOConstants.nTypeMask) != MachOConstants.nUndef,
              isObjCMetadataSymbol(reader: reader, symbolOffset: symbolOffset, sections: sections)
        else {
            return
        }

        // Clear `N_PEXT` and set `N_EXT` so `ld` exports ObjC runtime metadata symbols.
        buffer[typeOffset] = (symbolType & ~MachOConstants.nPext) | MachOConstants.nExt
    }

    /// Returns the external native definition name suitable for object-file deduplication.
    func externalNativeDefinitionName(
        reader: MachOReader,
        symbolOffset: Int,
        symbolTable: MachOSymbolTableInfo,
        sections: [MachOSection],
    ) -> String? {
        let stringIndex = Int(reader.readUInt32(at: symbolOffset + MachOSymbolLayout.stringIndexOffset))
        let typeOffset = symbolOffset + MachOSymbolLayout.typeOffset
        let descOffset = symbolOffset + MachOSymbolLayout.descriptionOffset
        guard descOffset + 2 <= reader.data.count else {
            return nil
        }

        let symbolType = reader.data[typeOffset]
        guard (symbolType & MachOConstants.nStabMask) == 0,
              (symbolType & MachOConstants.nExt) != 0,
              (symbolType & MachOConstants.nTypeMask) == MachOConstants.nSect,
              section(for: reader, symbolOffset: symbolOffset, sections: sections) != nil
        else {
            return nil
        }

        let description = reader.readUInt16(at: descOffset)
        guard (description & MachOConstants.nWeakDef) == 0 else {
            return nil
        }

        guard stringIndex < symbolTable.stringTableSize,
              let name = reader.cString(
                  at: symbolTable.stringTableOffset + stringIndex,
                  before: symbolTable.stringTableEnd,
              ),
              !isObjCMetadataSymbol(reader: reader, symbolOffset: symbolOffset, sections: sections)
        else {
            return nil
        }

        return name
    }

    /// Returns `true` when the symbol is defined in an Objective-C metadata section.
    func isObjCMetadataSymbol(reader: MachOReader, symbolOffset: Int, sections: [MachOSection]) -> Bool {
        section(for: reader, symbolOffset: symbolOffset, sections: sections)?.isObjCMetadataSection ?? false
    }

    /// Finds the section selected by an `N_SECT` entry and rejects invalid section indexes.
    func section(for reader: MachOReader, symbolOffset: Int, sections: [MachOSection]) -> MachOSection? {
        let sectionIndexOffset = symbolOffset + MachOSymbolLayout.sectionIndexOffset
        guard sectionIndexOffset < reader.data.count else {
            return nil
        }

        let sectionIndex = Int(reader.data[sectionIndexOffset])
        return sections.first { $0.index == sectionIndex }
    }
}
