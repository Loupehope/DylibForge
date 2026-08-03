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
        for command in commands where command.command == MachOConstants.lcLinkerOption && command.commandSize >= MachOLinkerOptionCommandLayout.size {
            let count = Int(reader.readUInt32(at: command.offset + MachOLinkerOptionCommandLayout.optionCountField))
            let stringsStart = command.offset + MachOLinkerOptionCommandLayout.size
            let stringsEnd = command.offset + command.commandSize
            options.append(contentsOf: parseNullTerminatedTokens(in: data, start: stringsStart, end: stringsEnd, count: count))
        }

        return options
    }

    /// Parses the Swift autolink section `__swift1_autolink_entries`.
    func parseSwiftAutolinkEntries(in data: Data) -> [String] {
        let reader = makeReader(for: data)
        return reader.sections()
            .filter { $0.sectionName == MachOSectionName.swiftAutolinkEntries }
            .compactMap { section in reader.range(offset: section.fileOffset, size: section.byteSize) }
            .flatMap { parseAutolinkTokens(from: reader.data[$0]) }
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
