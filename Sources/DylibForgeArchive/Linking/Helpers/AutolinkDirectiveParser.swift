import Foundation

/// Parses a flat linker-token list into a structured `AutolinkDirectives`.
final class AutolinkDirectiveParser {
    /// Parses `ld` tokens into framework/library/search path dependencies.
    func parse(_ tokens: [String]) -> AutolinkDirectives {
        let collector = AutolinkDirectiveCollector()
        var index = 0

        while index < tokens.count {
            let token = tokens[index]
            let nextToken = index + 1 < tokens.count ? tokens[index + 1] : nil

            let consumedTokens = collectStructuredLinkerToken(token, nextToken: nextToken, collector: collector)
            if consumedTokens > 0 {
                index += consumedTokens
                continue
            }

            index += 1
        }

        return AutolinkDirectives(
            frameworkPaths: collector.frameworkPaths,
            libraryPaths: collector.libraryPaths,
            frameworks: collector.frameworks,
            weakFrameworks: collector.weakFrameworks,
            libraries: collector.libraries,
            weakLibraries: collector.weakLibraries,
        )
    }
}

private extension AutolinkDirectiveParser {
    /// Collects structured linker arguments and reports how many tokens were consumed.
    func collectStructuredLinkerToken(_ token: String, nextToken: String?, collector: AutolinkDirectiveCollector) -> Int {
        let twoTokenOptions: [(String, ReferenceWritableKeyPath<AutolinkDirectiveCollector, Set<String>>)] = [
            ("-framework", \.frameworks),
            ("-weak_framework", \.weakFrameworks),
            ("-F", \.frameworkPaths),
            ("-L", \.libraryPaths),
            ("-l", \.libraries),
            ("-weak-l", \.weakLibraries),
        ]

        if token == "-Xlinker" {
            return nextToken == nil ? 1 : 2
        }

        for (option, keyPath) in twoTokenOptions where token == option {
            guard let nextToken else {
                return 1
            }
            collector.insert(nextToken, into: keyPath)
            return 2
        }

        let gluedOptions: [(String, ReferenceWritableKeyPath<AutolinkDirectiveCollector, Set<String>>)] = [
            ("-F", \.frameworkPaths),
            ("-L", \.libraryPaths),
            ("-l", \.libraries),
            ("-weak-l", \.weakLibraries),
        ]

        for (prefix, keyPath) in gluedOptions where token.hasPrefix(prefix) && token != prefix {
            collector.insert(String(token.dropFirst(prefix.count)), into: keyPath)
            return 1
        }

        return 0
    }
}

/// Temporary token accumulator before final plan creation.
final class AutolinkDirectiveCollector {
    var frameworkPaths = Set<String>()
    var libraryPaths = Set<String>()
    var frameworks = Set<String>()
    var weakFrameworks = Set<String>()
    var libraries = Set<String>()
    var weakLibraries = Set<String>()

    func insert(_ value: String, into keyPath: ReferenceWritableKeyPath<AutolinkDirectiveCollector, Set<String>>) {
        guard !value.isEmpty else {
            return
        }
        self[keyPath: keyPath].insert(value)
    }
}
