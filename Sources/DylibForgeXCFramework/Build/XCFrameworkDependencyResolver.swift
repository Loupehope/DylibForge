import Foundation
import Logging

/// Selects the dependency artifact that matches each architecture currently being relinked.
final class XCFrameworkDependencyResolver {
    private let files: XCFrameworkFiles
    private let dependencyURLs: [URL]
    private let logger: Logger

    init(
        paths: [String],
        files: XCFrameworkFiles,
        logger: Logger = Logger(label: "dylib-forge.xcframework"),
    ) throws {
        self.files = files
        self.logger = logger
        dependencyURLs = try paths.map { path in
            let url = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
            guard url.pathExtension == "xcframework", files.isDirectory(at: url) else {
                throw XCFrameworkError.message("Expected an XCFramework dependency: \(url.path)")
            }
            return url
        }
    }

    /// Returns linker arguments keyed by the architecture that consumes them.
    func linkerArgs(for library: XCFrameworkLibrary) throws -> [String: [String]] {
        guard !dependencyURLs.isEmpty else {
            return [:]
        }
        guard !library.supportedArchitectures.isEmpty else {
            throw XCFrameworkError.message("AvailableLibraries item has no SupportedArchitectures: \(library.identifier)")
        }
        guard Set(library.supportedArchitectures).count == library.supportedArchitectures.count else {
            throw XCFrameworkError.message("AvailableLibraries item has duplicate SupportedArchitectures: \(library.identifier)")
        }
        let dependencies = try dependencyURLs.map(parseDependency)
        return try Dictionary(uniqueKeysWithValues: library.supportedArchitectures.map { architecture in
            try (architecture, linkerArgs(for: library, architecture: architecture, dependencies: dependencies))
        })
    }
}

private extension XCFrameworkDependencyResolver {
    struct Dependency {
        let url: URL
        let manifest: XCFrameworkManifest
    }

    func parseDependency(at url: URL) throws -> Dependency {
        let manifestURL = url.appendingPathComponent("Info.plist")
        guard files.fileExists(at: manifestURL) else {
            throw XCFrameworkError.message("XCFramework dependency has no Info.plist: \(url.path)")
        }
        return try Dependency(url: url, manifest: files.readManifest(at: manifestURL))
    }

    func linkerArgs(
        for library: XCFrameworkLibrary,
        architecture: String,
        dependencies: [Dependency],
    ) throws -> [String] {
        let artifacts = try dependencies.map { dependency in
            try (dependency, matchingLibrary(in: dependency, for: library, architecture: architecture))
        }
        try rejectDuplicateFrameworkNames(in: artifacts, architecture: architecture)
        return try artifacts.flatMap { dependency, artifact in
            try linkerArgs(for: artifact, in: dependency.url)
        }
    }

    func matchingLibrary(
        in dependency: Dependency,
        for library: XCFrameworkLibrary,
        architecture: String,
    ) throws -> XCFrameworkLibrary {
        let matches = dependency.manifest.availableLibraries.filter {
            $0.supportedPlatform == library.supportedPlatform
                && $0.supportedPlatformVariant == library.supportedPlatformVariant
                && $0.supportedArchitectures.contains(architecture)
        }
        guard matches.count == 1, let match = matches.first else {
            let target = "\(library.supportedPlatform ?? "unknown")" + (library.supportedPlatformVariant.map { "-\($0)" } ?? "")
            throw XCFrameworkError.message(
                "Dependency \(dependency.url.lastPathComponent) has \(matches.isEmpty ? "no" : "multiple") \(target) artifact(s) for \(architecture)",
            )
        }
        return match
    }

    func rejectDuplicateFrameworkNames(
        in artifacts: [(Dependency, XCFrameworkLibrary)],
        architecture: String,
    ) throws {
        let frameworkNames = artifacts.compactMap { _, library -> String? in
            guard case .framework = library.artifactKind else {
                return nil
            }
            return URL(fileURLWithPath: library.libraryPath).deletingPathExtension().lastPathComponent
        }
        guard Set(frameworkNames).count == frameworkNames.count else {
            throw XCFrameworkError.message("Dependencies contain duplicate framework names for \(architecture)")
        }
    }

    func linkerArgs(for library: XCFrameworkLibrary, in xcframeworkURL: URL) throws -> [String] {
        let artifactURL = try library.artifactURL(in: xcframeworkURL)
        guard files.fileExists(at: artifactURL) else {
            throw XCFrameworkError.message("Dependency artifact does not exist: \(artifactURL.path)")
        }

        switch library.artifactKind {
        case .framework:
            let frameworkName = artifactURL.deletingPathExtension().lastPathComponent
            return ["-F", artifactURL.deletingLastPathComponent().path, "-framework", frameworkName]
        case .staticArchive:
            logger.warning("XCFramework dependency is a static archive and will be linked statically: \(artifactURL.path)")
            return [artifactURL.path]
        case .other:
            guard artifactURL.pathExtension == "dylib" else {
                throw XCFrameworkError.message("Unsupported XCFramework dependency artifact: \(artifactURL.path)")
            }
            return [artifactURL.path]
        }
    }
}
