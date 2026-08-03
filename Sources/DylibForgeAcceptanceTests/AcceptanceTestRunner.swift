import DylibForgeCore

/// Runs DylibForge's full end-to-end acceptance workflow.
public enum AcceptanceTestRunner {
    /// Builds fixtures, relinks them, and validates the generated macOS client.
    ///
    /// - Parameter xcodePath: An optional Xcode developer directory. When omitted, uses `xcode-select`.
    public static func run(xcodePath: String?) async throws {
        let logger = DylibForgeLogger()
        let suite = try await AcceptanceSuite(xcodePath: xcodePath)
        try suite.cleanBuildDirectory()
        try await logger.progressStep(message: "Building dylib-forge", successMessage: "Built dylib-forge") {
            try await suite.buildDylibForge()
        }
        try await logger.progressStep(message: "Building static fixtures", successMessage: "Built static fixtures") {
            try await suite.buildFixtures()
        }
        try await logger.progressStep(message: "Relinking fixture XCFrameworks", successMessage: "Relinked fixture XCFrameworks") {
            try await suite.relinkFixtures()
        }
        try await logger.progressStep(message: "Running acceptance tests", successMessage: "Ran acceptance tests") {
            try await suite.buildAndRunClient()
        }
    }
}
