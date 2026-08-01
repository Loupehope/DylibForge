import Foundation

/// Resolves an Xcode application bundle or the active Xcode selection into `DEVELOPER_DIR`.
public final class XcodePathProvider {
    private let commandExecutor: CommandExecutor

    /// Creates a provider that uses the default environment to resolve and validate Xcode paths.
    public init(commandExecutor: CommandExecutor = DefaultCommandExecutor()) {
        self.commandExecutor = commandExecutor
    }

    /// Returns the supplied Xcode application's developer directory, or the current `xcode-select` selection.
    public func developerDirectory(for xcodePath: String?) async throws -> String {
        guard let xcodePath else {
            return try await selectedDeveloperDirectory()
        }

        try await validateXcode(at: xcodePath)
        return xcodePath
    }
}

private extension XcodePathProvider {
    func selectedDeveloperDirectory() async throws -> String {
        let developerDirectory = try await commandExecutor.run("xcode-select", "--print-path").stdout
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !developerDirectory.isEmpty else {
            throw DylibForgeError.message("Unable to determine the selected Xcode developer directory")
        }

        try await validateXcode(at: developerDirectory)
        return developerDirectory
    }

    func validateXcode(at xcodePath: String) async throws {
        _ = try await commandExecutor.run(
            "env",
            "DEVELOPER_DIR=\(xcodePath)",
            "xcodebuild",
            "-version",
        )
    }
}
