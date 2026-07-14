import Foundation
import Logging
import Yams

/// Filters auto-detected framework dependencies that the selected SDK does not allow direct clients to link.
final class AutolinkFrameworkFilter {
    private let fileManager: FileManager
    private let yamlDecoder: YAMLDecoder

    /// Creates a filter with an injectable file manager so tests can provide an isolated SDK-like filesystem.
    init(fileManager: FileManager = .default, yamlDecoder: YAMLDecoder = YAMLDecoder()) {
        self.fileManager = fileManager
        self.yamlDecoder = yamlDecoder
    }

    /// Returns frameworks that are safe to pass to the linker as auto-detected dependencies.
    ///
    /// Some SDK stubs declare `allowable-clients`, which means `ld` rejects direct linkage from any other
    /// product. When that metadata exists, the framework is kept only if the linked product is explicitly listed.
    /// Frameworks without a readable stub, or without `allowable-clients`, are treated as public and kept.
    func allowedFrameworks(_ frameworks: Set<String>, context: DynamicSliceLinkContext) -> [String] {
        frameworks
            .filter { isFrameworkAllowed($0, context: context) }
            .sorted()
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
    /// Explicit `-F` search paths are included before the SDK root in `context.frameworkSearchRoots`, so vendored
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

    /// Decodes the TAPI YAML document and returns the client list that applies to this architecture/platform.
    func parseAllowedClients(fromTBDStub stub: String, target: String) -> Set<String>? {
        guard let metadata = try? yamlDecoder.decode(TBDMetadata.self, from: stub),
              let allowableClients = metadata.allowableClients
        else {
            return nil
        }

        return Set(
            allowableClients
                .filter { entry in
                    entry.targets?.contains(target) ?? true
                }
                .flatMap(\.clients)
                .filter { $0 != "-allowable_client" },
        )
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

/// Partial TAPI `.tbd` document decoded only for its direct-link client restrictions.
private struct TBDMetadata: Decodable {
    /// Per-target client allowlists declared by the stub, if it restricts direct linkage.
    let allowableClients: [TBDAllowableClients]?

    enum CodingKeys: String, CodingKey {
        case allowableClients = "allowable-clients"
    }
}

/// One architecture/platform-specific `allowable-clients` entry from a TAPI `.tbd` document.
private struct TBDAllowableClients: Decodable {
    /// TAPI target triples to which this allowlist applies; absent means it applies to every target.
    let targets: [String]?

    /// Product names permitted to link directly against the stub for the matching targets.
    let clients: [String]
}
