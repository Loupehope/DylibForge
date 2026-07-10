import Foundation

/// Reads a Unix `ar` archive and converts its members into convenient objects.
final class ArArchiveReader {
    private let archiveMagic = "!<arch>\n"
    private let headerSize = 60

    /// Checks the magic header and decides whether the payload is an `ar` archive.
    func isArchive(_ data: Data) -> Bool {
        String(decoding: data.prefix(8), as: UTF8.self) == archiveMagic
    }

    /// Sequentially reads all archive members with BSD long-name support (`#1/<len>`).
    func members(in archiveData: Data) throws -> [ArArchiveMember] {
        var offset = archiveMagic.utf8.count
        var members: [ArArchiveMember] = []
        var gnuLongNameTable: Data?

        while offset < archiveData.count {
            let member = try readMember(
                from: archiveData,
                offset: offset,
                gnuLongNameTable: gnuLongNameTable,
            )
            members.append(member)
            if member.name == "//" {
                gnuLongNameTable = member.payload
            }
            offset = alignedNextOffset(after: member.dataEnd)
        }

        return members
    }
}

private extension ArArchiveReader {
    /// Reads one member header and computes the name and payload range.
    func readMember(
        from archiveData: Data,
        offset: Int,
        gnuLongNameTable: Data?,
    ) throws -> ArArchiveMember {
        guard offset + headerSize <= archiveData.count else {
            throw DylibForgeError.message("Archive ended unexpectedly while reading a member header")
        }

        let header = archiveData[offset ..< (offset + headerSize)]
        guard String(decoding: header.suffix(2), as: UTF8.self) == "`\n" else {
            throw DylibForgeError.message("Malformed archive member header at offset \(offset)")
        }

        var memberName = String(decoding: header.prefix(16), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let size = try parseDecimalField(header.dropFirst(48).prefix(10))
        let dataStart = offset + headerSize
        let dataEnd = dataStart + size

        guard dataEnd <= archiveData.count else {
            throw DylibForgeError.message("Archive ended unexpectedly while reading member data")
        }

        var payloadStart = dataStart
        if memberName.hasPrefix("#1/") {
            let nameLength = try parseDecimalField(memberName.dropFirst(3).utf8[...])
            guard nameLength <= size else {
                throw DylibForgeError.message("Invalid archive member name length: \(memberName)")
            }
            memberName = String(decoding: archiveData[dataStart ..< (dataStart + nameLength)], as: UTF8.self)
                .trimmingCharacters(in: .controlCharacters)
            payloadStart += nameLength
        } else if isGNULongNameReference(memberName) {
            guard let gnuLongNameTable else {
                throw DylibForgeError.message("Archive member references a missing GNU long-name table: \(memberName)")
            }
            let nameOffset = try parseDecimalField(memberName.dropFirst().utf8[...])
            memberName = try gnuLongName(from: gnuLongNameTable, offset: nameOffset)
        } else if memberName != "/", memberName != "//", memberName.hasSuffix("/") {
            memberName.removeLast()
        }

        return ArArchiveMember(
            name: memberName,
            payload: Data(archiveData[payloadStart ..< dataEnd]),
            dataEnd: dataEnd,
        )
    }

    /// Returns `true` for GNU/SysV long-name references like `/123`, but not special members `/` or `//`.
    func isGNULongNameReference(_ memberName: String) -> Bool {
        guard memberName.hasPrefix("/"), memberName != "/", memberName != "//" else {
            return false
        }
        return memberName.dropFirst().allSatisfy(\.isNumber)
    }

    /// Resolves a GNU/SysV long member name from the archive string table.
    func gnuLongName(from table: Data, offset: Int) throws -> String {
        guard offset >= 0, offset < table.count else {
            throw DylibForgeError.message("Invalid GNU long-name table offset: \(offset)")
        }

        var end = offset
        while end < table.count, table[end] != 0x0A {
            end += 1
        }

        var name = String(decoding: table[offset ..< end], as: UTF8.self)
            .trimmingCharacters(in: .controlCharacters)
        if name.hasSuffix("/") {
            name.removeLast()
        }
        return name
    }

    /// Converts a decimal field from an `ar` header into an `Int`.
    func parseDecimalField(_ field: some Collection<UInt8>) throws -> Int {
        let text = String(decoding: field, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            return 0
        }
        guard let value = Int(text) else {
            throw DylibForgeError.message("Invalid numeric field in archive header: \(text)")
        }
        return value
    }

    /// Accounts for the padding byte: `ar` aligns members to an even boundary.
    func alignedNextOffset(after dataEnd: Int) -> Int {
        dataEnd.isMultiple(of: 2) ? dataEnd : dataEnd + 1
    }
}

/// One `ar` archive member with a normalized name and payload bytes.
struct ArArchiveMember {
    let name: String
    let payload: Data
    let dataEnd: Int

    /// Stores the member name, contents, and data end in the source archive.
    init(name: String, payload: Data, dataEnd: Int) {
        self.name = name
        self.payload = payload
        self.dataEnd = dataEnd
    }

    /// Returns the member basename because archives may contain path-like names.
    var baseName: String {
        URL(fileURLWithPath: name).lastPathComponent
    }

    /// Returns `true` for bookkeeping members that are not object files.
    var isArchiveIndex: Bool {
        name == "/" || name == "//" || name.hasPrefix("__.SYMDEF")
    }
}
