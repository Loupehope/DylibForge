import MachO

/// Typed aliases for constants imported from Apple's `mach-o/loader.h` and `mach-o/nlist.h`.
enum MachOConstants {
    static let mhMagic = UInt32(MH_MAGIC)
    static let mhMagic64 = UInt32(MH_MAGIC_64)
    static let mhObject = UInt32(MH_OBJECT)
    static let mhDylib = UInt32(MH_DYLIB)

    static let nStabMask = UInt8(N_STAB)
    static let nPext = UInt8(N_PEXT)
    static let nExt = UInt8(N_EXT)
    static let nTypeMask = UInt8(N_TYPE)
    static let nUndef = UInt8(N_UNDF)
    static let nSect = UInt8(N_SECT)
    static let nWeakDef = UInt16(N_WEAK_DEF)

    static let lcSegment = UInt32(LC_SEGMENT)
    static let lcSegment64 = UInt32(LC_SEGMENT_64)
    static let lcSymtab = UInt32(LC_SYMTAB)
    static let lcLinkerOption = UInt32(LC_LINKER_OPTION)
}

/// Validates that an Apple SDK C structure exposes a field addressable through Swift's `MemoryLayout` API.
enum MachOLayoutValidator {
    static func requiredOffset<T>(_: T.Type, of keyPath: PartialKeyPath<T>) -> Int {
        guard let offset = MemoryLayout<T>.offset(of: keyPath) else {
            fatalError("Unsupported Apple Mach-O SDK layout: cannot determine offset for \(keyPath) in \(T.self).")
        }
        return offset
    }
}

/// Describes the basic Mach-O header layout: 32/64-bit mode and header size.
struct MachOLayout {
    let is64Bit: Bool
    let headerSize: Int

    static let headerSize32 = MemoryLayout<mach_header>.size
    static let headerSize64 = MemoryLayout<mach_header_64>.size
    static let fileTypeOffset = MachOLayoutValidator.requiredOffset(mach_header.self, of: \.filetype)
    static let commandCountOffset = MachOLayoutValidator.requiredOffset(mach_header.self, of: \.ncmds)
    static let commandsSizeOffset = MachOLayoutValidator.requiredOffset(mach_header.self, of: \.sizeofcmds)
}

/// Layout shared by the `nlist` and `nlist_64` prefixes used by this tool.
enum MachOSymbolLayout {
    // `n_un` is a C union whose first member is `n_strx`; Swift cannot form a stable key path through it.
    static let stringIndexOffset = MachOLayoutValidator.requiredOffset(nlist.self, of: \.n_un)
    static let typeOffset = MachOLayoutValidator.requiredOffset(nlist.self, of: \.n_type)
    static let sectionIndexOffset = MachOLayoutValidator.requiredOffset(nlist.self, of: \.n_sect)
    static let descriptionOffset = MachOLayoutValidator.requiredOffset(nlist.self, of: \.n_desc)

    static func entrySize(for layout: MachOLayout) -> Int {
        layout.is64Bit ? MemoryLayout<nlist_64>.size : MemoryLayout<nlist>.size
    }
}

/// Fixed layout of the `symtab_command` load command from `mach-o/loader.h`.
enum MachOSymtabCommandLayout {
    static let size = MemoryLayout<symtab_command>.size
    static let symbolTableOffsetField = MachOLayoutValidator.requiredOffset(symtab_command.self, of: \.symoff)
    static let symbolCountField = MachOLayoutValidator.requiredOffset(symtab_command.self, of: \.nsyms)
    static let stringTableOffsetField = MachOLayoutValidator.requiredOffset(symtab_command.self, of: \.stroff)
    static let stringTableSizeField = MachOLayoutValidator.requiredOffset(symtab_command.self, of: \.strsize)
}

/// Fixed layout of the `linker_option_command` load command from `mach-o/loader.h`.
enum MachOLinkerOptionCommandLayout {
    static let size = MemoryLayout<linker_option_command>.size
    static let optionCountField = MachOLayoutValidator.requiredOffset(linker_option_command.self, of: \.count)
}

/// Names of sections interpreted by DylibForge.
enum MachOSectionName {
    static let swiftAutolinkEntries = "__swift1_autolink_entries"
}

/// Common prefix of every Mach-O load command: `uint32_t cmd; uint32_t cmdsize`.
enum MachOLoadCommandLayout {
    static let headerSize = MemoryLayout<load_command>.size
    static let sizeField = MachOLayoutValidator.requiredOffset(load_command.self, of: \.cmdsize)
}

/// Layout of `segment_command` / `segment_command_64` and their section records.
struct MachOSegmentLayout {
    let command: UInt32
    let commandHeaderSize: Int
    let sectionCountField: Int
    let sectionRecordSize: Int
    let sectionNameField: Int
    let sectionSegmentNameField: Int
    let sectionFileOffsetField: Int
    let sectionByteSizeField: Int
    let sectionByteSizeIs64Bit: Bool

    static let fixedNameLength = MemoryLayout.size(ofValue: section_64().sectname)
    static let bit32 = MachOSegmentLayout(
        command: MachOConstants.lcSegment,
        commandHeaderSize: MemoryLayout<segment_command>.size,
        sectionCountField: MachOLayoutValidator.requiredOffset(segment_command.self, of: \.nsects),
        sectionRecordSize: MemoryLayout<section>.size,
        sectionNameField: MachOLayoutValidator.requiredOffset(section.self, of: \.sectname),
        sectionSegmentNameField: MachOLayoutValidator.requiredOffset(section.self, of: \.segname),
        sectionFileOffsetField: MachOLayoutValidator.requiredOffset(section.self, of: \.offset),
        sectionByteSizeField: MachOLayoutValidator.requiredOffset(section.self, of: \.size),
        sectionByteSizeIs64Bit: false,
    )
    static let bit64 = MachOSegmentLayout(
        command: MachOConstants.lcSegment64,
        commandHeaderSize: MemoryLayout<segment_command_64>.size,
        sectionCountField: MachOLayoutValidator.requiredOffset(segment_command_64.self, of: \.nsects),
        sectionRecordSize: MemoryLayout<section_64>.size,
        sectionNameField: MachOLayoutValidator.requiredOffset(section_64.self, of: \.sectname),
        sectionSegmentNameField: MachOLayoutValidator.requiredOffset(section_64.self, of: \.segname),
        sectionFileOffsetField: MachOLayoutValidator.requiredOffset(section_64.self, of: \.offset),
        sectionByteSizeField: MachOLayoutValidator.requiredOffset(section_64.self, of: \.size),
        sectionByteSizeIs64Bit: true,
    )
}

/// Represents one load command with its file offset.
struct MachOLoadCommand {
    let command: UInt32
    let commandSize: Int
    let offset: Int
}

/// Stores `LC_SYMTAB` coordinates: symbol table and string table locations.
struct MachOSymbolTableInfo {
    let symbolTableOffset: Int
    let symbolCount: Int
    let stringTableOffset: Int
    let stringTableSize: Int

    var stringTableEnd: Int {
        stringTableOffset + stringTableSize
    }
}

/// One Mach-O section in the same one-based order used by `nlist.n_sect`.
struct MachOSection {
    let index: Int
    let segmentName: String
    let sectionName: String
    let fileOffset: Int
    let byteSize: Int

    var isObjCMetadataSection: Bool {
        segmentName.lowercased().hasPrefix("__objc") || sectionName.lowercased().hasPrefix("__objc")
    }
}
