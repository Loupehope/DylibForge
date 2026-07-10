import Files
import Foundation

final class ProjectFiles {
    var currentDirectoryPath: String {
        Folder.current.path
    }

    var temporaryDirectory: URL {
        Folder.temporary.url
    }

    func fileExists(atPath path: String) -> Bool {
        (try? File(path: path)) != nil || (try? Folder(path: path)) != nil
    }

    func isDirectory(atPath path: String) -> Bool {
        (try? Folder(path: path)) != nil
    }

    func createDirectory(at url: URL) throws {
        _ = try Folder.root.createSubfolderIfNeeded(at: url.path)
    }

    func removeItem(at url: URL) throws {
        if let file = try? File(path: url.path) {
            try file.delete()
            return
        }

        try Folder(path: url.path).delete()
    }

    func copyItem(at source: URL, to destination: URL) throws {
        if source.standardizedFileURL == destination.standardizedFileURL {
            return
        }

        if fileExists(atPath: destination.path) {
            try removeItem(at: destination)
        }

        if let file = try? File(path: source.path) {
            let destinationFile = try Folder.root.createFileIfNeeded(at: destination.path)
            try destinationFile.write(file.read())
        } else {
            let parent = try Folder.root.createSubfolderIfNeeded(at: destination.deletingLastPathComponent().path)
            let copied = try Folder(path: source.path).copy(to: parent)
            if copied.name != destination.lastPathComponent {
                try copied.rename(to: destination.lastPathComponent)
            }
        }
    }

    func contentsOfDirectory(at url: URL) throws -> [URL] {
        let folder = try Folder(path: url.path)
        let files = folder.files.includingHidden
        let subfolders = folder.subfolders.includingHidden
        return files.map(\.url) + subfolders.map(\.url)
    }

    func readFile(at url: URL) throws -> Data {
        try File(path: url.path).read()
    }

    func write(_ data: Data, to url: URL) throws {
        let file = try Folder.root.createFileIfNeeded(at: url.path)
        try file.write(data)
    }

    func write(_ string: String, to url: URL) throws {
        let file = try Folder.root.createFileIfNeeded(at: url.path)
        try file.write(string)
    }
}
