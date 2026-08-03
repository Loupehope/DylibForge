import ArgumentParser
import DylibForgeArchive
import DylibForgeCore
import DylibForgeXCFramework
import Foundation

struct DylibForgeXCFrameworkCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "xc",
        abstract: "Convert static XCFramework artifacts into dynamic libraries.",
        aliases: ["xcframework"],
    )

    @Argument(help: "Path to the input XCFramework.")
    var input: String

    @Option(help: "Output path for the generated XCFramework. Input may be reused for in-place conversion.")
    var output: String

    @Option(help: "Path to an Xcode.app bundle. Defaults to the Xcode selected by xcode-select.")
    var xcodePath: String?

    @Option(parsing: .unconditionalSingleValue, help: "SDK name or any followed by raw linker arguments.")
    var linkerArgSDK: [String] = []

    @Option(parsing: .unconditionalSingleValue, help: "SDK name or any followed by autolink dependency names to ignore.")
    var ignoreAutolinkSDK: [String] = []

    @Option(parsing: .unconditionalSingleValue, help: "SDK name or any followed by object file name substrings to skip.")
    var excludeObjectSDK: [String] = []

    @Option(help: "XCFramework dependency. Its matching platform and architecture slice is linked automatically.")
    var xcframeworkDependency: [String] = []

    @Flag(help: "Show logs at all levels.")
    var verbose = false

    func run() async throws {
        DylibForgeLogger.configure(verbose: verbose)
        let logger = DylibForgeLogger()

        do {
            try await logger.progressStep(
                message: "Converting \(input)",
                successMessage: "Converted \(output)",
            ) {
                try await DylibForgeXCFramework.run(
                    inputPath: input,
                    outputPath: output,
                    sdkArguments: XCFrameworkSDKArguments(
                        linkerArgs: linkerArgSDK,
                        ignoredAutolinkDependencies: ignoreAutolinkSDK,
                        excludedObjectNamePatterns: excludeObjectSDK,
                    ),
                    xcframeworkDependencies: xcframeworkDependency,
                    xcodePath: xcodePath,
                )
            }
        } catch {
            logger.error("\(ErrorPresenter.message(for: error))")
            throw ExitCode.failure
        }
    }
}
