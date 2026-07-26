import Foundation

/// Foundation-backed file-system facade shared by the core build pipeline.
final class ProjectFiles {
    private let files = FileManager.default

    var currentDirectoryPath: String {
        files.currentDirectoryPath
    }

    var temporaryDirectory: URL {
        URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
    }

    func fileExists(atPath path: String) -> Bool {
        files.fileExists(atPath: path)
    }

    func isDirectory(atPath path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return files.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    func createDirectory(at url: URL) throws {
        try files.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func removeItem(at url: URL) throws {
        try files.removeItem(at: url)
    }

    func copyItem(at source: URL, to destination: URL) throws {
        if source.standardizedFileURL == destination.standardizedFileURL {
            return
        }

        if fileExists(atPath: destination.path) {
            try removeItem(at: destination)
        }

        try createDirectory(at: destination.deletingLastPathComponent())
        try files.copyItem(at: source, to: destination)
    }

    func contentsOfDirectory(at url: URL) throws -> [URL] {
        try files.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: nil,
            options: [],
        )
    }

    func readFile(at url: URL) throws -> Data {
        try Data(contentsOf: url)
    }

    func write(_ data: Data, to url: URL) throws {
        try createDirectory(at: url.deletingLastPathComponent())
        try data.write(to: url, options: .atomic)
    }

    func write(_ string: String, to url: URL) throws {
        try write(Data(string.utf8), to: url)
    }
}
