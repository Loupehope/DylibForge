import ArgumentParser

@main
struct DylibForgeCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "dylib-forge",
        abstract: "Convert static Apple archives and XCFrameworks into dynamic Mach-O libraries.",
        version: "2.0.0",
        subcommands: [
            DylibForgeArchiveCLI.self,
            DylibForgeXCFrameworkCLI.self,
        ],
    )
}
