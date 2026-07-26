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
    )

    @Argument(help: "Path to the input XCFramework.")
    var input: String

    @Option(help: "Output path for the generated XCFramework. Input may be reused for in-place conversion.")
    var output: String

    @Option(parsing: .unconditionalSingleValue, help: "Additional raw argument passed to clang while linking.")
    var linkerArg: [String] = []

    @Option(help: "Auto-detected autolink dependency name to ignore.")
    var ignoreAutolink: [String] = []

    @Option(help: "Object file name substring to skip while unpacking static archives.")
    var excludeObject: [String] = []

    func run() async throws {
        LoggingSystem.bootstrap { ColoredLogHandler.standardError(label: $0) }

        try await DylibForgeXCFramework.run(
            inputPath: input,
            outputPath: output,
            relinkOptions: RelinkOptions(
                linkerArgs: linkerArg,
                ignoredAutolinkDependencies: ignoreAutolink,
                excludedObjectNamePatterns: excludeObject,
            ),
        )
    }
}
