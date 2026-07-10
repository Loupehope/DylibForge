import Foundation

/// Extracts autolink directives from Mach-O object files.
final class MachOAutolinkParser {
    /// Parses `LC_LINKER_OPTION` as an array of linker tokens.
    func parseLinkerOptions(in data: Data) -> [String] {
        let reader = makeReader(for: data)
        guard let commands = reader.loadCommands() else {
            return []
        }

        var options: [String] = []
        for command in commands where command.command == MachOConstants.lcLinkerOption && command.commandSize >= 12 {
            let count = Int(reader.readUInt32(at: command.offset + 8))
            let stringsStart = command.offset + 12
            let stringsEnd = command.offset + command.commandSize
            options.append(contentsOf: parseNullTerminatedTokens(in: data, start: stringsStart, end: stringsEnd, count: count))
        }

        return options
    }

    /// Parses the Swift autolink section `__swift1_autolink_entries`.
    func parseSwiftAutolinkEntries(in data: Data) -> [String] {
        let reader = makeReader(for: data)
        guard let layout = reader.layout, let commands = reader.loadCommands() else {
            return []
        }

        var tokens: [String] = []
        for command in commands where isSegmentCommand(command.command, layout: layout) {
            tokens.append(contentsOf: parseAutolinkTokensFromSegment(reader: reader, command: command, layout: layout))
        }

        return tokens
    }
}

private extension MachOAutolinkParser {
    /// Creates a reader with the same dependencies as the current autolink parser.
    func makeReader(for data: Data) -> MachOReader {
        MachOReader(data: data)
    }

    /// Reads the requested number of null-terminated strings from the `LC_LINKER_OPTION` payload.
    func parseNullTerminatedTokens(in data: Data, start: Int, end: Int, count: Int) -> [String] {
        var cursor = start
        var tokens: [String] = []

        for _ in 0 ..< count {
            guard cursor < end else {
                break
            }
            guard let zeroIndex = data[cursor ..< end].firstIndex(of: 0) else {
                break
            }

            let token = data[cursor ..< zeroIndex].utf8
            if !token.isEmpty {
                tokens.append(token)
            }
            cursor = zeroIndex + 1
        }

        return tokens
    }

    /// Checks whether the load command is a 32-bit or 64-bit segment command.
    func isSegmentCommand(_ command: UInt32, layout: MachOLayout) -> Bool {
        (layout.is64Bit && command == MachOConstants.lcSegment64) ||
            (!layout.is64Bit && command == MachOConstants.lcSegment)
    }

    /// Walks segment sections and collects tokens from Swift autolink sections.
    func parseAutolinkTokensFromSegment(
        reader: MachOReader,
        command: MachOLoadCommand,
        layout: MachOLayout,
    ) -> [String] {
        let sectionCount = Int(reader.readUInt32(at: command.offset + (layout.is64Bit ? 64 : 48)))
        let sectionOffset = command.offset + (layout.is64Bit ? 72 : 56)
        let sectionSize = layout.is64Bit ? 80 : 68
        var tokens: [String] = []

        for sectionIndex in 0 ..< sectionCount {
            let current = sectionOffset + (sectionIndex * sectionSize)
            guard current + sectionSize <= command.offset + command.commandSize else {
                break
            }

            guard sectionName(reader: reader, offset: current) == "__swift1_autolink_entries",
                  let sectionRange = autolinkSectionRange(reader: reader, offset: current, layout: layout)
            else {
                continue
            }

            tokens.append(contentsOf: parseAutolinkTokens(from: reader.data[sectionRange]))
        }

        return tokens
    }

    /// Reads the section name from a `section` / `section_64` record.
    func sectionName(reader: MachOReader, offset: Int) -> String? {
        reader.data[offset ..< (offset + 16)].utf8
            .split(separator: "\0", maxSplits: 1)
            .first
            .map(String.init)
    }

    /// Computes the file range for the autolink entries section contents.
    func autolinkSectionRange(reader: MachOReader, offset: Int, layout: MachOLayout) -> Range<Int>? {
        let fileOffset = Int(reader.readUInt32(at: offset + (layout.is64Bit ? 48 : 40)))
        let sectionByteSize = layout.is64Bit
            ? Int(reader.readUInt64(at: offset + 40))
            : Int(reader.readUInt32(at: offset + 36))
        guard fileOffset + sectionByteSize <= reader.data.count else {
            return nil
        }

        return fileOffset ..< (fileOffset + sectionByteSize)
    }

    /// Converts Swift autolink section contents into linker tokens.
    func parseAutolinkTokens(from rawSection: some DataProtocol) -> [String] {
        let nullTokens = rawSection.split(separator: 0).map {
            $0.utf8.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }

        if !nullTokens.isEmpty {
            return nullTokens.flatMap(\.shellTokens)
        }

        let normalizedText = rawSection.utf8
            .replacingOccurrences(of: "\0", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return normalizedText.isEmpty ? [] : normalizedText.shellTokens
    }
}
