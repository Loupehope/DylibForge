import Foundation

/// Describes the basic Mach-O header layout: 32/64-bit mode and header size.
struct MachOLayout {
    let is64Bit: Bool
    let headerSize: Int
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
}

/// One Mach-O section in the same one-based order used by `nlist.n_sect`.
struct MachOSection {
    let index: Int
    let segmentName: String
    let sectionName: String

    var isObjCMetadataSection: Bool {
        segmentName.lowercased().hasPrefix("__objc") || sectionName.lowercased().hasPrefix("__objc")
    }
}

/// Safe low-level reader for the small Mach-O subset this tool needs.
final class MachOReader {
    let data: Data

    /// Accepts Mach-O bytes and dependencies for reading constants and strings.
    init(data: Data) {
        self.data = data
    }

    /// Detects the Mach-O format from magic bytes and returns the layout for subsequent reads.
    var layout: MachOLayout? {
        guard data.count >= 4 else {
            return nil
        }

        switch readUnalignedUInt32(at: 0) {
        case MachOConstants.mhMagic64.littleEndian:
            return MachOLayout(is64Bit: true, headerSize: 32)
        case MachOConstants.mhMagic.littleEndian:
            return MachOLayout(is64Bit: false, headerSize: 28)
        default:
            return nil
        }
    }

    /// Reads `filetype` from the Mach-O header when the file looks like a supported Mach-O.
    var fileType: UInt32? {
        guard layout != nil else {
            return nil
        }
        return readUInt32(at: 12)
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

        let commandCount = Int(readUInt32(at: 16))
        var offset = layout.headerSize
        var commands: [MachOLoadCommand] = []

        for _ in 0 ..< commandCount {
            guard offset + 8 <= data.count else {
                return nil
            }

            let command = readUInt32(at: offset)
            let commandSize = Int(readUInt32(at: offset + 4))
            guard commandSize > 0, offset + commandSize <= data.count else {
                return nil
            }

            commands.append(MachOLoadCommand(command: command, commandSize: commandSize, offset: offset))
            offset += commandSize
        }

        return commands
    }

    /// Finds `LC_SYMTAB` and returns symbol table and string table coordinates.
    func symbolTable() -> MachOSymbolTableInfo? {
        guard let commands = loadCommands() else {
            return nil
        }

        for command in commands where command.command == MachOConstants.lcSymtab {
            return MachOSymbolTableInfo(
                symbolTableOffset: Int(readUInt32(at: command.offset + 8)),
                symbolCount: Int(readUInt32(at: command.offset + 12)),
                stringTableOffset: Int(readUInt32(at: command.offset + 16)),
            )
        }

        return nil
    }

    /// Returns all section headers in the same one-based order used by symbol table entries.
    func sections() -> [MachOSection] {
        guard let layout, let commands = loadCommands() else {
            return []
        }

        var sections: [MachOSection] = []
        for command in commands {
            let segmentInfo = segmentSectionInfo(command: command, is64Bit: layout.is64Bit)
            guard let segmentInfo else {
                continue
            }

            for sectionIndex in 0 ..< segmentInfo.sectionCount {
                let sectionOffset = segmentInfo.sectionsOffset + (sectionIndex * segmentInfo.sectionSize)
                guard sectionOffset + segmentInfo.sectionSize <= data.count else {
                    return sections
                }

                sections.append(
                    MachOSection(
                        index: sections.count + 1,
                        segmentName: fixedString(at: sectionOffset + 16, length: 16),
                        sectionName: fixedString(at: sectionOffset, length: 16),
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

        let nlistSize = layout.is64Bit ? 16 : 12
        return (0 ..< symbolTable.symbolCount).compactMap { index in
            let offset = symbolTable.symbolTableOffset + (index * nlistSize)
            return offset + nlistSize <= data.count ? offset : nil
        }
    }

    /// Reads a little-endian `UInt16` from an arbitrary offset.
    func readUInt16(at offset: Int) -> UInt16 {
        UInt16(littleEndian: readUnalignedUInt16(at: offset))
    }

    /// Reads a little-endian `UInt32` from an arbitrary offset.
    func readUInt32(at offset: Int) -> UInt32 {
        UInt32(littleEndian: readUnalignedUInt32(at: offset))
    }

    /// Reads a little-endian `UInt64` from an arbitrary offset.
    func readUInt64(at offset: Int) -> UInt64 {
        UInt64(littleEndian: readUnalignedUInt64(at: offset))
    }

    /// Reads a null-terminated C string from the Mach-O string table.
    func cString(at offset: Int) -> String? {
        guard offset >= 0, offset < data.count else {
            return nil
        }
        guard let zeroIndex = data[offset ..< data.count].firstIndex(of: 0) else {
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

    /// Reads `UInt32` byte-by-byte without requiring pointer alignment.
    func readUnalignedUInt32(at offset: Int) -> UInt32 {
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

    /// Reads `UInt16` byte-by-byte without requiring pointer alignment.
    func readUnalignedUInt16(at offset: Int) -> UInt16 {
        guard offset >= 0, offset + 2 <= data.count else {
            assertionFailure("Out-of-bounds UInt16 read at offset \(offset), dataSize=\(data.count)")
            return 0
        }

        let b0 = UInt16(data[offset])
        let b1 = UInt16(data[offset + 1]) << 8
        return b0 | b1
    }

    /// Reads `UInt64` byte-by-byte without requiring pointer alignment.
    func readUnalignedUInt64(at offset: Int) -> UInt64 {
        guard offset >= 0, offset + 8 <= data.count else {
            assertionFailure("Out-of-bounds UInt64 read at offset \(offset), dataSize=\(data.count)")
            return 0
        }

        let lower = UInt64(readUnalignedUInt32(at: offset))
        let upper = UInt64(readUnalignedUInt32(at: offset + 4)) << 32
        return lower | upper
    }
}

private extension MachOReader {
    /// Extracts the section table coordinates from `LC_SEGMENT` or `LC_SEGMENT_64`.
    func segmentSectionInfo(command: MachOLoadCommand, is64Bit: Bool) -> (
        sectionCount: Int,
        sectionsOffset: Int,
        sectionSize: Int,
    )? {
        if is64Bit {
            guard command.command == MachOConstants.lcSegment64, command.commandSize >= 72 else {
                return nil
            }

            return (
                sectionCount: Int(readUInt32(at: command.offset + 64)),
                sectionsOffset: command.offset + 72,
                sectionSize: 80,
            )
        }

        guard command.command == MachOConstants.lcSegment, command.commandSize >= 56 else {
            return nil
        }

        return (
            sectionCount: Int(readUInt32(at: command.offset + 48)),
            sectionsOffset: command.offset + 56,
            sectionSize: 68,
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
