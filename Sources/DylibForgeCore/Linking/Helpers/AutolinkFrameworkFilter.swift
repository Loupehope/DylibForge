import Foundation

/// Filters auto-detected framework dependencies that the selected SDK does not allow direct clients to link.
final class AutolinkFrameworkFilter {
    private let fileManager: FileManager

    /// Creates a filter with an injectable file manager so tests can provide an isolated SDK-like filesystem.
    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
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
        guard let allowedClients = allowedClients(
            forFramework: framework,
            context: context,
        ) else {
            return true
        }

        return allowedClients.contains(context.linkedProductName)
    }

    /// Reads the first matching framework stub and extracts its `allowable-clients` entries.
    ///
    /// A `nil` return means "no restriction known": either the stub was not found/readable, or the stub does
    /// not declare `allowable-clients`. The caller intentionally treats that as allowed, matching normal linker
    /// behavior for public frameworks.
    func allowedClients(forFramework framework: String, context: DynamicSliceLinkContext) -> Set<String>? {
        // Search explicit `-F` paths before SDK defaults, matching how linker framework lookup is normally ordered.
        for frameworkStubURL in frameworkStubURLs(forFramework: framework, context: context) {
            guard
                fileManager.fileExists(atPath: frameworkStubURL.path),
                let stub = try? String(contentsOf: frameworkStubURL, encoding: .utf8)
            else {
                continue
            }

            return parseAllowedClients(fromTBDStub: stub)
        }

        return nil
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
                rootURL.appendingPathComponent("System/Library/PrivateFrameworks/\(frameworkRelativePath)"),
            ]
        }
    }

    /// Extracts all client names from a TAPI `.tbd` `allowable-clients` block.
    ///
    /// The project only needs a tiny slice of the YAML-ish `.tbd` format. This deliberately avoids introducing
    /// a YAML dependency: it locates the top-level `allowable-clients:` block and then reads every bracketed
    /// `clients: [ ... ]` list inside it.
    func parseAllowedClients(fromTBDStub stub: String) -> Set<String>? {
        guard let allowableClientsRange = stub.range(of: "allowable-clients:") else {
            return nil
        }

        // The block continues while subsequent lines are indented. The next non-indented key starts a new block.
        let remainingStub = stub[allowableClientsRange.upperBound...]
        let blockLines = remainingStub
            .split(separator: "\n", omittingEmptySubsequences: false)
            .prefix { line in
                line.isEmpty || line.first?.isWhitespace == true
            }
        let allowableClientsBlock = blockLines.joined(separator: "\n")
        var clients = Set<String>()

        for clientList in bracketedValues(named: "clients", in: allowableClientsBlock) {
            clients.formUnion(clientList)
        }

        return clients
    }

    /// Parses repeated `key: [ value, ... ]` lists from a text block.
    ///
    /// TAPI may wrap long arrays across multiple lines, so the parser searches from `[` to the matching `]`
    /// instead of assuming the list ends on the same line as the key.
    func bracketedValues(named key: String, in text: String) -> [[String]] {
        var values: [[String]] = []
        var searchStart = text.startIndex

        while let keyRange = text.range(of: "\(key):", range: searchStart ..< text.endIndex),
              let openingBracket = text[keyRange.upperBound...].firstIndex(of: "["),
              let closingBracket = text[openingBracket...].firstIndex(of: "]")
        {
            let rawValues = text[text.index(after: openingBracket) ..< closingBracket]

            // Values are plain framework/product names in current SDK stubs, sometimes quoted in older formats.
            let parsedValues = rawValues
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "'\""))) }
                .filter { !$0.isEmpty }

            values.append(parsedValues)
            searchStart = text.index(after: closingBracket)
        }

        return values
    }
}
