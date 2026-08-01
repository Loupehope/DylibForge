import ArgumentParser
import DylibForgeCore
import Foundation
import Logging

@main
struct DylibForgeCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "dylib-forge",
        abstract: "Relink a static Apple ar archive into a dynamic Mach-O binary.",
        version: "1.5.0",
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
    }
}
