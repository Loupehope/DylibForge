/// Runs DylibForge's full end-to-end acceptance workflow.
public enum AcceptanceTestRunner {
    /// Builds fixtures, relinks them, and validates the generated macOS client.
    ///
    /// - Parameter xcodePath: An optional Xcode developer directory. When omitted, uses `xcode-select`.
    public static func run(xcodePath: String?) async throws {
        let suite = try await AcceptanceSuite(xcodePath: xcodePath)
        try suite.cleanBuildDirectory()
        try await suite.buildDylibForge()
        try await suite.buildFixtures()
        try await suite.relinkFixtures()
        try await suite.buildAndRunClient()
    }
}
