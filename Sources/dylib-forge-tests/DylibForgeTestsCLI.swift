import ArgumentParser
import DylibForgeAcceptanceTests
import DylibForgeCore

/// The command-line entry point for DylibForge's end-to-end acceptance suite.
@main
struct DylibForgeTestsCLI: AsyncParsableCommand {
    /// Declares the acceptance subcommand.
    static let configuration = CommandConfiguration(
        commandName: "dylib-forge-tests",
        abstract: "Run DylibForge acceptance tests.",
        subcommands: [Acceptance.self],
    )
}

/// Runs the complete DylibForge acceptance suite.
private struct Acceptance: AsyncParsableCommand {
    /// Configures the acceptance subcommand.
    static let configuration = CommandConfiguration(
        commandName: "acceptance",
        abstract: "Build, relink, and run acceptance fixtures.",
    )

    @Option(help: "Path to an Xcode.app bundle. Defaults to the Xcode selected by xcode-select.")
    var xcodePath: String?

    @Flag(help: "Show logs at all levels.")
    var verbose = false

    /// Runs the entire acceptance workflow with one selected Xcode toolchain.
    mutating func run() async throws {
        DylibForgeLogger.configure(verbose: verbose)
        let logger = DylibForgeLogger()

        do {
            try await AcceptanceTestRunner.run(xcodePath: xcodePath)
        } catch {
            logger.error("\(ErrorPresenter.message(for: error))")
            throw ExitCode.failure
        }
    }
}
