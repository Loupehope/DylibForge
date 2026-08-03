import DylibForgeCore
import Foundation

/// File-system and property-list operations used by XCFramework conversion.
final class XCFrameworkFiles {
    private let files = FileManager.default

    /// Reports whether a file-system item exists at the URL.
    func fileExists(at url: URL) -> Bool {
        files.fileExists(atPath: url.path)
    }

    /// Reports whether the URL exists and represents a directory.
    func isDirectory(at url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return files.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    /// Copies an XCFramework tree, replacing an existing destination only after its parent exists.
    func copyItem(at source: URL, to destination: URL) throws {
        try files.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        if files.fileExists(atPath: destination.path) {
            try files.removeItem(at: destination)
        }
        try files.copyItem(at: source, to: destination)
    }

    /// Removes a file or directory that is no longer part of the output XCFramework.
    func removeItem(at url: URL) throws {
        try files.removeItem(at: url)
    }

    /// Removes an item only when it still exists, which is useful for temporary conversion directories.
    func removeItemIfExists(at url: URL) throws {
        guard files.fileExists(atPath: url.path) else {
            return
        }
        try files.removeItem(at: url)
    }

    /// Moves a completed sibling conversion directory into place, replacing an existing output when necessary.
    func replaceOutput(at outputURL: URL, with completedURL: URL) throws {
        if files.fileExists(atPath: outputURL.path) {
            _ = try files.replaceItemAt(outputURL, withItemAt: completedURL)
        } else {
            try files.moveItem(at: completedURL, to: outputURL)
        }
    }

    /// Decodes and validates the root XCFramework `Info.plist`.
    func readManifest(at url: URL) throws -> XCFrameworkManifest {
        try XCFrameworkManifest(propertyList: readPropertyList(at: url))
    }

    /// Persists the updated root manifest as an XML property list.
    func writeManifest(_ manifest: XCFrameworkManifest, to url: URL) throws {
        try writePropertyList(manifest.encodedPropertyList, to: url)
    }

    /// Decodes the metadata needed to rebuild a framework's executable.
    func readBundleInfo(at frameworkURL: URL) throws -> XCFrameworkBundleInfo {
        try XCFrameworkBundleInfo(
            propertyList: readPropertyList(at: bundleInfoURL(in: frameworkURL)),
            frameworkURL: frameworkURL,
        )
    }

    /// Removes signature directories and embedded Mach-O signatures from copied artifacts.
    ///
    /// The input signature cannot remain valid after a binary is replaced, so the output is deliberately unsigned.
    func removeCodeSignatures(from root: URL, libraries: [XCFrameworkLibrary]) throws {
        try removeCodeSignatureDirectories(from: root)
        for library in libraries {
            try removeBinaryCodeSignature(from: library.artifactURL(in: root))
        }
    }
}

private extension XCFrameworkFiles {
    /// Loads a dictionary property list while rejecting unsupported top-level forms.
    func readPropertyList(at url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        let propertyList = try PropertyListSerialization.propertyList(from: data, format: nil)
        guard let dictionary = propertyList as? [String: Any] else {
            throw DylibForgeError.message("Expected a dictionary property list: \(url.path)")
        }
        return dictionary
    }

    /// Serializes a property-list dictionary in a stable, human-readable format.
    func writePropertyList(_ propertyList: [String: Any], to url: URL) throws {
        let data = try PropertyListSerialization.data(fromPropertyList: propertyList, format: .xml, options: 0)
        try data.write(to: url, options: .atomic)
    }

    /// Locates framework metadata in either a flat iOS-style bundle or a versioned macOS-style bundle.
    func bundleInfoURL(in frameworkURL: URL) throws -> URL {
        let candidateURLs = [
            frameworkURL.appendingPathComponent("Info.plist"),
            frameworkURL.appendingPathComponent("Resources/Info.plist"),
        ]
        guard let infoURL = candidateURLs.first(where: { files.fileExists(atPath: $0.path) }) else {
            throw DylibForgeError.message("Framework Info.plist does not exist: \(frameworkURL.path)")
        }
        return infoURL
    }

    /// Deletes bundle `_CodeSignature` directories without traversing their contents.
    func removeCodeSignatureDirectories(from root: URL) throws {
        let enumerator = files.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles],
        )
        var signatureDirectories: [URL] = []

        while let item = enumerator?.nextObject() as? URL {
            if item.lastPathComponent == "_CodeSignature" {
                signatureDirectories.append(item)
                enumerator?.skipDescendants()
            }
        }

        for directory in signatureDirectories {
            try files.removeItem(at: directory)
        }
    }

    /// Asks `codesign` to remove a Mach-O signature, ignoring unsigned artifacts.
    func removeBinaryCodeSignature(from artifactURL: URL) {
        let targetURL = signedBinaryURL(for: artifactURL)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = ["--remove-signature", targetURL.path]
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        guard (try? process.run()) != nil else {
            return
        }
        process.waitUntilExit()
    }

    /// Returns a framework executable when needed; dylibs can be passed to `codesign` directly.
    func signedBinaryURL(for artifactURL: URL) -> URL {
        guard artifactURL.pathExtension == "framework",
              let bundleInfo = try? readBundleInfo(at: artifactURL)
        else {
            return artifactURL
        }
        return artifactURL.appendingPathComponent(bundleInfo.executableName)
    }
}
