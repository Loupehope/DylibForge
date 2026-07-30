import ArgumentParser
import DylibForgeCore
import DylibForgeXCFramework
import Foundation
import Logging

@main
struct DylibForgeXCFrameworkCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "dylib-forge-xc",
        abstract: "Convert static XCFramework artifacts into dynamic libraries.",
        version: "1.5.0",
    )

    @Argument(help: "Path to the input XCFramework.")
    var input: String

    @Option(help: "Output path for the generated XCFramework. Input may be reused for in-place conversion.")
    var output: String

    @Option(parsing: .unconditionalSingleValue, help: "SDK name or any followed by raw linker arguments.")
    var linkerArgSDK: [String] = []

    @Option(parsing: .unconditionalSingleValue, help: "SDK name or any followed by autolink dependency names to ignore.")
    var ignoreAutolinkSDK: [String] = []

    @Option(parsing: .unconditionalSingleValue, help: "SDK name or any followed by object file name substrings to skip.")
    var excludeObjectSDK: [String] = []

    @Option(help: "XCFramework dependency. Its matching platform and architecture slice is linked automatically.")
    var xcframeworkDependency: [String] = []

    func run() async throws {
        LoggingSystem.bootstrap { ColoredLogHandler.standardError(label: $0) }

        try await DylibForgeXCFramework.run(
            inputPath: input,
            outputPath: output,
            sdkArguments: XCFrameworkSDKArguments(
                linkerArgs: linkerArgSDK,
                ignoredAutolinkDependencies: ignoreAutolinkSDK,
                excludedObjectNamePatterns: excludeObjectSDK,
            ),
            xcframeworkDependencies: xcframeworkDependency,
        )
    }
}
