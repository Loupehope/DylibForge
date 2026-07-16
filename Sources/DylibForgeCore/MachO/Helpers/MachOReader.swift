import Foundation

/// Safe low-level reader for the small Mach-O subset this tool needs.
final class MachOReader {
    let data: Data
    let layout: MachOLayout?

    /// Accepts Mach-O bytes and dependencies for reading constants and strings.
    init(data: Data) {
        self.data = data
        guard data.count >= 4 else {
            layout = nil
            return
        }

        switch Self.readLittleEndianUInt32(in: data, at: 0) {
        case MachOConstants.mhMagic64:
            layout = MachOLayout(is64Bit: true, headerSize: MachOLayout.headerSize64)
        case MachOConstants.mhMagic:
            layout = MachOLayout(is64Bit: false, headerSize: MachOLayout.headerSize32)
        default:
            layout = nil
        }
    }

    /// Reads `filetype` from the Mach-O header when the file looks like a supported Mach-O.
    var fileType: UInt32? {
        guard let layout, data.count >= layout.headerSize else {
            return nil
        }
        return readUInt32(at: MachOLayout.fileTypeOffset)
    }

    /// Returns `true` when the file is a relocatable object (`MH_OBJECT`).
    var isObject: Bool {
        fileType == MachOConstants.mhObject
    }

    /// Sequentially reads and validates all load commands from the Mach-O header.
    func loadCommands() -> [MachOLoadCommand]? {
        guard let layout else {
            return nil
        }

        let commandCount = Int(readUInt32(at: MachOLayout.commandCountOffset))
        let commandsSize = Int(readUInt32(at: MachOLayout.commandsSizeOffset))
        var offset = layout.headerSize
        guard range(offset: offset, size: commandsSize) != nil else {
            return nil
        }
        let commandsEnd = offset + commandsSize
        var commands: [MachOLoadCommand] = []

        for _ in 0 ..< commandCount {
            guard offset + MachOLoadCommandLayout.headerSize <= commandsEnd else {
                return nil
            }

            let command = readUInt32(at: offset)
            let commandSize = Int(readUInt32(at: offset + MachOLoadCommandLayout.sizeField))
            guard commandSize >= MachOLoadCommandLayout.headerSize,
                  commandSize.isMultiple(of: 4),
                  commandSize <= commandsEnd - offset
            else {
                return nil
            }

            commands.append(MachOLoadCommand(command: command, commandSize: commandSize, offset: offset))
            offset += commandSize
        }

        return offset == commandsEnd ? commands : nil
    }

    /// Finds `LC_SYMTAB` and returns symbol table and string table coordinates.
    func symbolTable() -> MachOSymbolTableInfo? {
        guard let commands = loadCommands() else {
            return nil
        }

        for command in commands where command.command == MachOConstants.lcSymtab {
            guard let layout, command.commandSize >= MachOSymtabCommandLayout.size else {
                return nil
            }

            let symbolTableOffset = Int(readUInt32(at: command.offset + MachOSymtabCommandLayout.symbolTableOffsetField))
            let symbolCount = Int(readUInt32(at: command.offset + MachOSymtabCommandLayout.symbolCountField))
            let stringTableOffset = Int(readUInt32(at: command.offset + MachOSymtabCommandLayout.stringTableOffsetField))
            let stringTableSize = Int(readUInt32(at: command.offset + MachOSymtabCommandLayout.stringTableSizeField))
            let symbolEntrySize = MachOSymbolLayout.entrySize(for: layout)
            guard symbolCount <= Int.max / symbolEntrySize,
                  range(offset: symbolTableOffset, size: symbolCount * symbolEntrySize) != nil,
                  range(offset: stringTableOffset, size: stringTableSize) != nil
            else {
                return nil
            }

            return MachOSymbolTableInfo(
                symbolTableOffset: symbolTableOffset,
                symbolCount: symbolCount,
                stringTableOffset: stringTableOffset,
                stringTableSize: stringTableSize,
            )
        }

        return nil
    }

    /// Returns section headers in the same one-based order used by symbol table entries.
    /// Invalid or unsupported input has no usable sections and therefore returns an empty array.
    func sections() -> [MachOSection] {
        guard let layout, let commands = loadCommands() else {
            return []
        }

        var sections: [MachOSection] = []
        for command in commands {
            let segmentInfo = segmentSectionInfo(command: command, layout: layout)
            guard let segmentInfo else {
                if command.command == MachOConstants.lcSegment || command.command == MachOConstants.lcSegment64 {
                    return []
                }
                continue
            }

            for sectionIndex in 0 ..< segmentInfo.sectionCount {
                let sectionOffset = segmentInfo.sectionsOffset + (sectionIndex * segmentInfo.sectionSize)
                guard sectionOffset <= data.count - segmentInfo.sectionSize,
                      let byteSize = sectionByteSize(at: sectionOffset, layout: segmentInfo.layout)
                else {
                    return []
                }

                sections.append(
                    MachOSection(
                        index: sections.count + 1,
                        segmentName: fixedString(at: sectionOffset + segmentInfo.layout.sectionSegmentNameField, length: MachOSegmentLayout.fixedNameLength),
                        sectionName: fixedString(at: sectionOffset + segmentInfo.layout.sectionNameField, length: MachOSegmentLayout.fixedNameLength),
                        fileOffset: Int(readUInt32(at: sectionOffset + segmentInfo.layout.sectionFileOffsetField)),
                        byteSize: byteSize,
                    ),
                )
            }
        }

        return sections
    }

    /// Returns valid offsets for all `nlist` entries inside the symbol table.
    func symbolOffsets(in symbolTable: MachOSymbolTableInfo) -> [Int] {
        guard let layout else {
            return []
        }

        let entrySize = MachOSymbolLayout.entrySize(for: layout)
        return (0 ..< symbolTable.symbolCount).map { index in
            symbolTable.symbolTableOffset + (index * entrySize)
        }
    }

    /// Reads a little-endian `UInt16` from an arbitrary offset.
    func readUInt16(at offset: Int) -> UInt16 {
        readLittleEndianUInt16(at: offset)
    }

    /// Reads a little-endian `UInt32` from an arbitrary offset.
    func readUInt32(at offset: Int) -> UInt32 {
        readLittleEndianUInt32(at: offset)
    }

    /// Reads a little-endian `UInt64` from an arbitrary offset.
    func readUInt64(at offset: Int) -> UInt64 {
        readLittleEndianUInt64(at: offset)
    }

    /// Reads a null-terminated C string from the Mach-O string table.
    func cString(at offset: Int, before endOffset: Int) -> String? {
        guard offset >= 0, offset < endOffset, endOffset <= data.count else {
            return nil
        }
        guard let zeroIndex = data[offset ..< endOffset].firstIndex(of: 0) else {
            return nil
        }
        return data[offset ..< zeroIndex].utf8
    }

    /// Reads a fixed-width null-padded string from a Mach-O header field.
    func fixedString(at offset: Int, length: Int) -> String {
        guard offset >= 0, length >= 0, offset + length <= data.count else {
            return ""
        }

        let bytes = data[offset ..< (offset + length)]
        let endIndex = bytes.firstIndex(of: 0) ?? bytes.endIndex
        return bytes[bytes.startIndex ..< endIndex].utf8
    }

    /// Reads a little-endian `UInt32` byte-by-byte without requiring pointer alignment.
    func readLittleEndianUInt32(at offset: Int) -> UInt32 {
        guard offset >= 0, offset + 4 <= data.count else {
            assertionFailure("Out-of-bounds UInt32 read at offset \(offset), dataSize=\(data.count)")
            return 0
        }

        let b0 = UInt32(data[offset])
        let b1 = UInt32(data[offset + 1]) << 8
        let b2 = UInt32(data[offset + 2]) << 16
        let b3 = UInt32(data[offset + 3]) << 24
        return b0 | b1 | b2 | b3
    }

    /// Reads a little-endian `UInt16` byte-by-byte without requiring pointer alignment.
    func readLittleEndianUInt16(at offset: Int) -> UInt16 {
        guard offset >= 0, offset + 2 <= data.count else {
            assertionFailure("Out-of-bounds UInt16 read at offset \(offset), dataSize=\(data.count)")
            return 0
        }

        let b0 = UInt16(data[offset])
        let b1 = UInt16(data[offset + 1]) << 8
        return b0 | b1
    }

    /// Reads a little-endian `UInt64` byte-by-byte without requiring pointer alignment.
    func readLittleEndianUInt64(at offset: Int) -> UInt64 {
        guard offset >= 0, offset + 8 <= data.count else {
            assertionFailure("Out-of-bounds UInt64 read at offset \(offset), dataSize=\(data.count)")
            return 0
        }

        let lower = UInt64(readLittleEndianUInt32(at: offset))
        let upper = UInt64(readLittleEndianUInt32(at: offset + 4)) << 32
        return lower | upper
    }

    /// Returns a file range without allowing integer overflow in `offset + size`.
    func range(offset: Int, size: Int) -> Range<Int>? {
        guard offset >= 0, size >= 0, offset <= data.count, size <= data.count - offset else {
            return nil
        }
        return offset ..< (offset + size)
    }

    private static func readLittleEndianUInt32(in data: Data, at offset: Int) -> UInt32 {
        let b0 = UInt32(data[offset])
        let b1 = UInt32(data[offset + 1]) << 8
        let b2 = UInt32(data[offset + 2]) << 16
        let b3 = UInt32(data[offset + 3]) << 24
        return b0 | b1 | b2 | b3
    }
}

private extension MachOReader {
    /// Reads the `size` field from a `section` / `section_64` record without narrowing a large 64-bit value.
    func sectionByteSize(at sectionOffset: Int, layout: MachOSegmentLayout) -> Int? {
        if layout.sectionByteSizeIs64Bit {
            return Int(exactly: readUInt64(at: sectionOffset + layout.sectionByteSizeField))
        }
        return Int(readUInt32(at: sectionOffset + layout.sectionByteSizeField))
    }

    /// Extracts the section table coordinates from `LC_SEGMENT` or `LC_SEGMENT_64`.
    func segmentSectionInfo(command: MachOLoadCommand, layout: MachOLayout) -> (
        sectionCount: Int,
        sectionsOffset: Int,
        sectionSize: Int,
        layout: MachOSegmentLayout,
    )? {
        let segmentLayout = layout.is64Bit ? MachOSegmentLayout.bit64 : MachOSegmentLayout.bit32
        guard command.command == segmentLayout.command,
              command.commandSize >= segmentLayout.commandHeaderSize
        else {
            return nil
        }

        let sectionCount = Int(readUInt32(at: command.offset + segmentLayout.sectionCountField))
        guard sectionCount <= (command.commandSize - segmentLayout.commandHeaderSize) / segmentLayout.sectionRecordSize else {
            return nil
        }

        return (
            sectionCount: sectionCount,
            sectionsOffset: command.offset + segmentLayout.commandHeaderSize,
            sectionSize: segmentLayout.sectionRecordSize,
            layout: segmentLayout,
        )
    }
}

/// Decodes Mach-O string fields and splits autolink strings into linker tokens.
extension DataProtocol {
    /// Decodes a binary field as UTF-8, returning an empty string for invalid bytes.
    var utf8: String {
        String(bytes: self, encoding: .utf8) ?? ""
    }
}

extension String {
    /// Splits a shell-like autolink string into tokens while respecting single and double quotes.
    var shellTokens: [String] {
        var tokens: [String] = []
        var current = ""
        var quote: Character?

        for character in self {
            if let activeQuote = quote {
                if character == activeQuote {
                    quote = nil
                } else {
                    current.append(character)
                }
                continue
            }

            if character == "'" || character == "\"" {
                quote = character
            } else if character.isWhitespace {
                appendToken(&current, to: &tokens)
            } else {
                current.append(character)
            }
        }

        appendToken(&current, to: &tokens)
        return tokens
    }

    /// Appends the accumulated token to the result and clears the buffer.
    private func appendToken(_ current: inout String, to tokens: inout [String]) {
        guard !current.isEmpty else {
            return
        }
        tokens.append(current)
        current.removeAll(keepingCapacity: true)
    }
}
