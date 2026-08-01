import Foundation
import Logging
import Yams

/// Filters auto-detected framework dependencies that the selected SDK does not allow direct clients to link.
final class AutolinkFrameworkFilter {
    private let fileManager: FileManager
    private let jsonDecoder: JSONDecoder
    private let yamlDecoder: YAMLDecoder
    private let logger: Logger

    /// Creates a filter with an injectable file manager so tests can provide an isolated SDK-like filesystem.
    init(
        fileManager: FileManager = .default,
        jsonDecoder: JSONDecoder = JSONDecoder(),
        yamlDecoder: YAMLDecoder = YAMLDecoder(),
        logger: Logger = Logger(label: "dylib-forge.autolink-filter"),
    ) {
        self.fileManager = fileManager
        self.jsonDecoder = jsonDecoder
        self.yamlDecoder = yamlDecoder
        self.logger = logger
    }

    /// Returns frameworks that are safe to pass to the linker as auto-detected dependencies.
    ///
    /// Some SDK stubs declare `allowable-clients`, which means `ld` rejects direct linkage from any other
    /// product. When that metadata exists, the framework is kept only if the linked product is explicitly listed.
    /// Frameworks without a readable stub, or without `allowable-clients`, are treated as public and kept.
    func allowedTBDFrameworks(_ frameworks: Set<String>, context: DynamicSliceLinkContext) -> Set<String> {
        Set(frameworks.filter { isFrameworkAllowed($0, context: context) })
    }

    /// Finds Swift compatibility libraries whose SDK stubs are aliases for frameworks.
    func allowedFrameworkAliases(forLibraries libraries: Set<String>, context: DynamicSliceLinkContext) -> [String: Set<FrameworkAlias>] {
        Dictionary(
            uniqueKeysWithValues: libraries.compactMap { library in
                let frameworks = allowedFrameworkAliases(forLibrary: library, context: context)
                guard !frameworks.isEmpty else {
                    return nil
                }
                return (library, frameworks)
            },
        )
    }
}

private extension AutolinkFrameworkFilter {
    /// Checks a single framework against its `.tbd` client allowlist, if the SDK provides one.
    func isFrameworkAllowed(_ framework: String, context: DynamicSliceLinkContext) -> Bool {
        switch frameworkLinkability(
            forFramework: framework,
            context: context,
        ) {
        case .missing:
            // Preserve a genuinely missing dependency so the linker can report it to the user.
            true

        case .headerOnly:
            // SDK modules such as CoreAudioTypes expose headers but have no dylib or `.tbd` to link.
            false

        case .linkable(allowedClients: nil):
            true

        case let .linkable(allowedClients: allowedClients?):
            allowedClients.contains(context.linkedProductName)
        }
    }

    /// Locates a framework's linkable payload and, when present, its `.tbd` client allowlist.
    ///
    /// A framework directory without either a binary or `.tbd` is a header-only module rather than a valid linker
    /// input. A completely missing framework remains distinguishable so the linker can report that dependency.
    func frameworkLinkability(forFramework framework: String, context: DynamicSliceLinkContext) -> FrameworkLinkability {
        var foundFrameworkDirectory = false

        // Search explicit `-F` paths before SDK defaults, matching how linker framework lookup is normally ordered.
        for frameworkStubURL in frameworkStubURLs(forFramework: framework, context: context) {
            let frameworkURL = frameworkStubURL.deletingLastPathComponent()
            guard fileManager.fileExists(atPath: frameworkURL.path) else {
                continue
            }
            foundFrameworkDirectory = true

            let frameworkBinaryURL = frameworkStubURL.deletingPathExtension()
            guard fileManager.fileExists(atPath: frameworkStubURL.path) || fileManager.fileExists(atPath: frameworkBinaryURL.path) else {
                continue
            }

            guard let stub = try? String(contentsOf: frameworkStubURL, encoding: .utf8) else {
                return .linkable(allowedClients: nil)
            }

            return .linkable(
                allowedClients: parseAllowedClients(fromTBDStub: stub, target: context.targetTriples.tbd),
            )
        }

        return foundFrameworkDirectory ? .headerOnly : .missing
    }

    /// Builds candidate `.tbd` locations for a framework name.
    ///
    /// Explicit `-F` search paths are included before the SDK root in `context.frameworkSearchRoots`, so supplied
    /// SDK overlays can take precedence over platform SDK stubs. Inside each root, the lookup probes the public
    /// and private framework directories used by Apple SDKs.
    func frameworkStubURLs(forFramework framework: String, context: DynamicSliceLinkContext) -> [URL] {
        let frameworkRelativePath = "\(framework).framework/\(framework).tbd"
        return context.frameworkSearchRoots.flatMap { rootURL in
            [
                rootURL.appendingPathComponent(frameworkRelativePath),
                rootURL.appendingPathComponent("System/Library/Frameworks/\(frameworkRelativePath)"),
                rootURL.appendingPathComponent("System/Library/SubFrameworks/\(frameworkRelativePath)"),
                rootURL.appendingPathComponent("System/Library/PrivateFrameworks/\(frameworkRelativePath)"),
            ]
        }
    }

    /// Returns the frameworks represented by a Swift compatibility-library stub.
    func allowedFrameworkAliases(forLibrary library: String, context: DynamicSliceLinkContext) -> Set<FrameworkAlias> {
        guard library.hasPrefix("swift") else {
            return []
        }

        for rootURL in context.frameworkSearchRoots {
            let stubURLs = [
                rootURL.appendingPathComponent("System/Cryptexes/OS/usr/lib/swift/lib\(library).tbd"),
                rootURL.appendingPathComponent("usr/lib/swift/lib\(library).tbd"),
            ]
            for stubURL in stubURLs {
                guard let stub = try? String(contentsOf: stubURL, encoding: .utf8) else {
                    continue
                }

                if let allowableClients = parseAllowedClients(fromTBDStub: stub, target: context.targetTriples.tbd), !allowableClients.contains(
                    context.linkedProductName,
                ) {
                    continue
                }

                let frameworks = installNames(
                    fromTBDStub: stub,
                    target: context.targetTriples.tbd,
                ).compactMap {
                    frameworkAlias(fromInstallName: $0, sdkRoot: rootURL)
                }

                if !frameworks.isEmpty {
                    return Set(frameworks)
                }
            }
        }

        return []
    }

    /// Builds a framework name and its containing directory from an SDK install name.
    func frameworkAlias(fromInstallName installName: String, sdkRoot: URL) -> FrameworkAlias? {
        guard installName.hasPrefix("/") else {
            return nil
        }
        let installURL = URL(fileURLWithPath: installName)
        let components = installURL.pathComponents
        guard let frameworkIndex = components.lastIndex(where: { $0.hasSuffix(".framework") }) else {
            return nil
        }

        let frameworkComponent = components[frameworkIndex]
        let frameworkName = String(frameworkComponent.dropLast(".framework".count))
        guard components.last == frameworkName else {
            return nil
        }

        var frameworkURL = installURL
        while frameworkURL.lastPathComponent != frameworkComponent {
            frameworkURL.deleteLastPathComponent()
        }
        let frameworkSearchRoot = sdkRoot.appendingPathComponent(
            String(frameworkURL.deletingLastPathComponent().path.dropFirst()),
        )
        return FrameworkAlias(name: frameworkName, frameworkSearchRoot: frameworkSearchRoot)
    }

    /// Decodes a TAPI JSON or YAML document and returns the client list that applies to this architecture/platform.
    func parseAllowedClients(fromTBDStub stub: String, target: String) -> Set<String>? {
        let jsonAllowableClients = jsonAllowableClients(in: stub) // TAPI v5+
        let yamlAllowableClients = yamlAllowableClients(in: stub, target: target) // TAPI v4
        if let allowableClients = jsonAllowableClients ?? yamlAllowableClients {
            return filteredClients(from: allowableClients, target: target)
        }

        return nil
    }

    /// Reads every install name from either current TAPI representation.
    func installNames(fromTBDStub stub: String, target: String) -> [String] {
        if let metadata = try? jsonDecoder.decode(TBDJSONMetadata.self, from: Data(stub.utf8)), metadata.version >= 5 {
            if metadata.version > 5 {
                logger.warning("TAPI JSON v\(metadata.version) is not explicitly supported; using the v5 decoder.")
            }

            return metadata.mainLibrary.installNames.map(\.name)
        }

        let metadata = directYAMLMetadata(in: stub, target: target)
        if !metadata.isEmpty {
            return metadata.map(\.installName)
        }

        return []
    }

    /// Applies the current TAPI target selection to a v4/v5 client allowlist.
    func filteredClients(from allowableClients: [TBDAllowableClients], target: String) -> Set<String> {
        Set(
            allowableClients
                .filter { entry in entry.targets?.contains(where: { targetMatches($0, linkedSliceTarget: target) }) ?? true }
                .flatMap(\.clients)
                .filter { $0 != "-allowable_client" },
        )
    }

    /// Matches a requested TAPI target, treating an `arm64e` SDK entry as applicable to the matching `arm64` slice.
    func targetMatches(_ stubTarget: String, linkedSliceTarget: String) -> Bool {
        if stubTarget == linkedSliceTarget {
            return true
        }

        return stubTarget == "arm64e-\(linkedSliceTarget.dropFirst("arm64-".count))"
    }

    /// Decodes TAPI v5 JSON. Newer JSON versions deliberately reuse this model until their schema changes.
    func jsonAllowableClients(in stub: String) -> [TBDAllowableClients]? {
        let data = Data(stub.utf8)
        guard let metadata = try? jsonDecoder.decode(TBDJSONMetadata.self, from: data),
              metadata.version >= 5
        else {
            return nil
        }
        if metadata.version > 5 {
            logger.warning("TAPI JSON v\(metadata.version) is not explicitly supported; using the v5 decoder.")
        }
        return metadata.allowableClients
    }

    /// Decodes TAPI v4 YAML only after its version marker confirms the schema.
    func yamlAllowableClients(in stub: String, target: String) -> [TBDAllowableClients]? {
        let metadata = directYAMLMetadata(in: stub, target: target)
        guard metadata.contains(where: { $0.allowableClients != nil }) else {
            return nil
        }
        return metadata.flatMap { $0.allowableClients ?? [] }
    }

    /// Removes documents that are explicitly declared as re-exports of another document in the same TAPI stream.
    func directYAMLMetadata(in stub: String, target: String) -> [TBDYAMLMetadata] {
        let metadata = yamlMetadata(in: stub).filter { $0.targets?.contains(where: { targetMatches($0, linkedSliceTarget: target) }) ?? true }
        let reexportedLibraries = Set(metadata.flatMap { document in
            document.reexportedLibraries?
                .filter { $0.targets?.contains(where: { targetMatches($0, linkedSliceTarget: target) }) ?? true }
                .flatMap(\.libraries) ?? []
        })
        return metadata.filter { !reexportedLibraries.contains($0.installName) }
    }

    /// Decodes every document in a TAPI v4 YAML stub.
    ///
    /// A stream can contain separate TAPI documents for re-exported libraries, so each document is decoded
    /// independently with Yams' native multi-document parser.
    func yamlMetadata(in stub: String) -> [TBDYAMLMetadata] {
        guard let documents = try? Array(compose_all(yaml: stub)) else {
            return []
        }
        return documents.compactMap { document in
            guard let metadata = try? yamlDecoder.decode(TBDYAMLMetadata.self, from: document),
                  metadata.version == 4
            else {
                return nil
            }
            return metadata
        }
    }
}

/// Whether framework lookup found a binary/stub linker input, a header-only module, or nothing at all.
private enum FrameworkLinkability {
    /// No framework directory was found; preserve the dependency for the linker to diagnose.
    case missing
    /// A framework directory exists but provides neither a binary nor a `.tbd` stub.
    case headerOnly
    /// A linkable framework, optionally restricted to the listed direct clients.
    case linkable(allowedClients: Set<String>?)
}

/// An SDK framework identified by a Swift compatibility-library stub.
struct FrameworkAlias: Hashable {
    let name: String
    /// Directory containing the framework bundle, suitable for `-F` lookup.
    let frameworkSearchRoot: URL
}

/// TAPI v4 YAML document with a top-level direct-link client allowlist.
private struct TBDYAMLMetadata: Decodable {
    let version: Int
    let targets: [String]?
    let allowableClients: [TBDAllowableClients]?
    let installName: String
    let reexportedLibraries: [TBDReexportedLibraries]?

    enum CodingKeys: String, CodingKey {
        case version = "tbd-version"
        case targets
        case allowableClients = "allowable-clients"
        case installName = "install-name"
        case reexportedLibraries = "reexported-libraries"
    }
}

/// One TAPI v4 re-export declaration.
private struct TBDReexportedLibraries: Decodable {
    let targets: [String]?
    let libraries: [String]
}

/// TAPI v5 JSON document with a nested main-library record.
private struct TBDJSONMetadata: Decodable {
    let version: Int
    let mainLibrary: TBDJSONMainLibrary

    var allowableClients: [TBDAllowableClients]? {
        mainLibrary.allowableClients
    }

    enum CodingKeys: String, CodingKey {
        case version = "tapi_tbd_version"
        case mainLibrary = "main_library"
    }
}

/// TAPI v5's main-library record.
private struct TBDJSONMainLibrary: Decodable {
    let allowableClients: [TBDAllowableClients]?
    let installNames: [TBDInstallName]

    enum CodingKeys: String, CodingKey {
        case allowableClients = "allowable_clients"
        case installNames = "install_names"
    }
}

/// One TAPI v5 install-name entry.
private struct TBDInstallName: Decodable {
    let name: String
}

/// One architecture/platform-specific `allowable-clients` entry from a TAPI `.tbd` document.
private struct TBDAllowableClients: Decodable {
    /// TAPI target triples to which this allowlist applies; absent means it applies to every target.
    let targets: [String]?

    /// Product names permitted to link directly against the stub for the matching targets.
    let clients: [String]
}
