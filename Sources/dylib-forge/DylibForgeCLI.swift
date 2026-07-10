import ArgumentParser
import DylibForgeCore
import Foundation
import Logging

@main
struct DylibForgeCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "dylib-forge",
        abstract: "Relink a static Apple ar archive into a dynamic Mach-O binary.",
    )

    @Argument(help: "Path to the input static ar archive or static framework binary.")
    var input: String

    @Option(help: "Output path for the generated dynamic binary.")
    var output: String

    @Option(help: "SDK to link against, for example iphoneos, iphonesimulator, watchos, or watchsimulator.")
    var sdk: String

    @Option(help: "Install name written into LC_ID_DYLIB, for example @rpath/Foo.framework/Foo.")
    var installName: String

    @Option(parsing: .unconditionalSingleValue, help: "Additional raw argument passed to clang while linking.")
    var linkerArg: [String] = []

    @Option(help: "Auto-detected autolink dependency name to ignore.")
    var ignoreAutolink: [String] = []

    @Option(help: "Object file name substring to skip while unpacking static archives.")
    var excludeObject: [String] = []

    func run() async throws {
        LoggingSystem.bootstrap { StreamLogHandler.standardError(label: $0) }

        try await DylibForge.run(
            inputPath: input,
            outputPath: output,
            sdk: sdk,
            relinkOptions: RelinkOptions(
                linkerArgs: linkerArg,
                ignoredAutolinkDependencies: ignoreAutolink,
                installName: installName,
                excludedObjectNamePatterns: excludeObject,
            ),
        )
    }
}
