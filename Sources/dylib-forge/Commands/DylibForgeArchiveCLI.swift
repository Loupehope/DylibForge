import ArgumentParser
import DylibForgeArchive
import DylibForgeCore
import Foundation
import Logging

struct DylibForgeArchiveCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "ar",
        abstract: "Relink a static Apple ar archive into a dynamic Mach-O binary.",
        aliases: ["archive"],
    )

    @Argument(help: "Path to the input static ar archive or static framework binary.")
    var input: String

    @Option(help: "Output path for the generated dynamic binary.")
    var output: String

    @Option(help: "SDK to link against, for example iphoneos, iphonesimulator, watchos, or watchsimulator.")
    var sdk: String

    @Option(help: "Install name written into LC_ID_DYLIB, for example @rpath/Foo.framework/Foo.")
    var installName: String

    @Option(help: "Path to an Xcode.app bundle. Defaults to the Xcode selected by xcode-select.")
    var xcodePath: String?

    @Option(parsing: .unconditionalSingleValue, help: "Additional raw argument passed to clang while linking.")
    var linkerArg: [String] = []

    @Option(help: "Auto-detected autolink dependency name to ignore.")
    var ignoreAutolink: [String] = []

    @Option(help: "Object file name substring to skip while unpacking static archives.")
    var excludeObject: [String] = []

    func run() async throws {
        LoggingSystem.bootstrap { ColoredLogHandler.standardError(label: $0) }
        let logger = Logger(label: "dylib-forge")

        do {
            try await DylibForge.run(
                inputPath: input,
                outputPath: output,
                sdk: sdk,
                installName: installName,
                relinkOptions: RelinkOptions(
                    linkerArgs: ScopedValues(base: linkerArg),
                    ignoredAutolinkDependencies: ScopedValues(base: ignoreAutolink),
                    excludedObjectNamePatterns: ScopedValues(base: excludeObject),
                ),
                xcodePath: xcodePath,
            )
        } catch {
            logger.error("\(ErrorPresenter.message(for: error))")
            throw ExitCode.failure
        }
    }
}
