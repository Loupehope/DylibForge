import ArgumentParser
import DylibForgeSubprocess
import Foundation
import Logging

/// Runs the acceptance pipeline from generated fixture source through client runtime validation.
///
/// The suite creates static XCFrameworks for every fixture and supported platform, converts them to
/// dynamic XCFrameworks, then verifies that a client can link and execute them on macOS, iOS Simulator,
/// and watchOS Simulator.
final class AcceptanceSuite: Sendable {
    private let acceptanceDirectory: URL
    private let repositoryDirectory: URL
    private let buildDirectory: URL
    private let logger: Logger
    private let shell: CommandExecutor
    private let developerDirectory: String

    private nonisolated(unsafe) let fileManager = FileManager.default

    /// Locates the repository and prepares a shared executor configured for the selected Xcode.
    ///
    /// - Parameter xcodePath: An optional Xcode developer directory; the current `xcode-select` value is
    ///   used when this is `nil`.
    init(xcodePath: String?) async throws {
        logger = Logger(label: "dylib-forge.acceptance")
        repositoryDirectory = try await Self.locateRepositoryDirectory(using: DefaultCommandExecutor(logger: logger))
        acceptanceDirectory = repositoryDirectory.appendingPathComponent("AcceptanceTests", isDirectory: true)
        buildDirectory = acceptanceDirectory.appendingPathComponent(".build", isDirectory: true)
        developerDirectory = try await XcodePathProvider(commandExecutor: DefaultCommandExecutor(logger: logger))
            .developerDirectory(for: xcodePath)
        shell = DeveloperCommandExecutor(developerDirectory: developerDirectory, logger: logger)

        guard fileManager.fileExists(atPath: repositoryDirectory.appendingPathComponent("Package.swift").path) else {
            throw ValidationError("Could not locate the DylibForge package root.")
        }
        guard fileManager.fileExists(atPath: acceptanceDirectory.path) else {
            throw ValidationError("Could not locate AcceptanceTests in the DylibForge package.")
        }
    }

    /// Removes all generated acceptance artifacts and creates a new build directory.
    func cleanBuildDirectory() throws {
        try removeIfPresent(buildDirectory)
        try fileManager.createDirectory(at: buildDirectory, withIntermediateDirectories: true)
    }

    /// Builds the `dylib-forge-xc` executable consumed by the relinking stage.
    func buildDylibForge() async throws {
        logger.notice("Building dylib-forge-xc")
        _ = try await shell.run([
            "swift", "build", "--package-path", repositoryDirectory.path, "--product", "dylib-forge-xc",
        ])
        logger.notice("Built dylib-forge-xc")
    }

    /// Generates the fixtures Xcode project and builds every platform slice.
    ///
    /// Each fixture's slices are archived concurrently, then combined into one static XCFramework that is
    /// used as input by the relinking stage.
    func buildFixtures() async throws {
        logger.notice("Generating the fixtures Xcode project")
        try await runXcodeGen(
            spec: fixturesProjectDirectory.appendingPathComponent("project.yml"),
            projectDirectory: fixturesProjectDirectory,
        )

        for fixture in Fixture.allCases {
            logger.notice("Building static fixture \(fixture.rawValue)")
            let frameworkURLs = try await archiveFrameworks(for: fixture)

            let outputURL = staticDirectory.appendingPathComponent("\(fixture.rawValue).xcframework")
            try removeIfPresent(outputURL)
            logger.notice("Creating static XCFramework \(fixture.rawValue)")
            var arguments = [
                "xcodebuild",
                "-create-xcframework",
            ]
            for frameworkURL in frameworkURLs {
                arguments += [fixture.archiveProduct.xcodebuildArgument, frameworkURL.path]
            }
            arguments += ["-output", outputURL.path]
            _ = try await shell.run(arguments.xcbeautified)
        }
    }

    /// Relinks each static fixture XCFramework with the locally built DylibForge executable.
    ///
    /// Fixtures without XCFramework dependencies run concurrently. Dependent fixtures run after their
    /// relinked dependencies have been produced.
    func relinkFixtures() async throws {
        logger.notice("Relinking fixture XCFrameworks")
        try fileManager.createDirectory(at: relinkedDirectory, withIntermediateDirectories: true)
        let forgeExecutable = repositoryDirectory.appendingPathComponent(".build/debug/dylib-forge-xc").path

        guard fileManager.isExecutableFile(atPath: forgeExecutable) else {
            throw ValidationError(
                "dylib-forge-xc is missing: \(forgeExecutable). Run the `run` command or build it first.",
            )
        }

        let independentFixtures = Fixture.allCases.filter(\.xcframeworkDependencies.isEmpty)
        _ = try await independentFixtures.concurrentMap { [weak self] fixture in
            guard let self else { throw CancellationError() }
            try await relink(fixture, using: forgeExecutable)
        }

        for fixture in Fixture.allCases where !fixture.xcframeworkDependencies.isEmpty {
            try await relink(fixture, using: forgeExecutable)
        }
    }

    /// Builds and launches the macOS client, then runs the Swift Testing bundles on simulators.
    ///
    /// The macOS client runs as a child process, so a dyld failure is reported immediately through its exit
    /// status without terminating the acceptance command itself.
    func buildAndRunClient() async throws {
        logger.notice("Generating the acceptance client Xcode project")
        try await runXcodeGen(
            spec: clientProjectDirectory.appendingPathComponent("project.yml"),
            projectDirectory: clientProjectDirectory,
        )
        logger.notice("Building the macOS acceptance client")
        let buildResult = try await shell.run([
            "xcodebuild",
            "build", "-project",
            clientProjectDirectory.appendingPathComponent("AcceptanceClient.xcodeproj").path,
            "-scheme", "AcceptanceClient", "-configuration", "Debug",
            "-destination", "platform=macOS,arch=arm64", "-derivedDataPath",
            clientDerivedDataDirectory.path,
            "CODE_SIGNING_ALLOWED=YES", "CODE_SIGN_IDENTITY=-",
        ].xcbeautified)
        try validateNoDuplicateSymbolDiagnostics(in: buildResult, logFileName: "client-build.log")

        logger.notice("Running the macOS acceptance client")
        _ = try await shell.run([clientExecutable.path])
        try await runSimulatorTests()

        logger.notice("Acceptance tests passed")
    }
}

private extension AcceptanceSuite {
    /// Archives every device and simulator slice for one fixture and returns framework URLs in platform order.
    ///
    /// The concurrent map limits active `xcodebuild archive` processes to the number of available processor
    /// cores while preserving `Platform.allCases` order for `xcodebuild -create-xcframework`.
    func archiveFrameworks(for fixture: Fixture) async throws -> [URL] {
        try await Platform.allCases.concurrentMap { [weak self] platform in
            guard let self else { throw CancellationError() }
            logger.info("Archiving \(fixture.rawValue) for \(platform.rawValue)")
            let archiveURL = archivesDirectory.appendingPathComponent("\(fixture.rawValue)-\(platform.rawValue).xcarchive")
            let derivedDataURL = fixtureDerivedDataDirectory(for: fixture, platform: platform)

            _ = try await shell.run([
                "xcodebuild",
                "archive", "-project",
                fixturesProjectDirectory.appendingPathComponent("Fixtures.xcodeproj").path,
                "-scheme", "\(fixture.rawValue)_\(platform.rawValue)", "-configuration", "Release",
                "-sdk", platform.sdk, "-destination", platform.destination,
                "-archivePath", archiveURL.path, "-derivedDataPath", derivedDataURL.path,
                "-quiet", "CODE_SIGNING_ALLOWED=NO",
            ].xcbeautified)
            return archiveURL.appendingPathComponent(fixture.archiveProduct.path(for: fixture))
        }
    }

    /// Converts one static fixture XCFramework and supplies its already-converted XCFramework dependencies.
    func relink(_ fixture: Fixture, using forgeExecutable: String) async throws {
        logger.info("Relinking \(fixture.rawValue)")
        let inputURL = staticDirectory.appendingPathComponent("\(fixture.rawValue).xcframework")
        let outputURL = relinkedDirectory.appendingPathComponent("\(fixture.rawValue).xcframework")
        try removeIfPresent(outputURL)
        let arguments =
            [
                inputURL.path,
                "--output", outputURL.path,
                "--xcode-path", developerDirectory,
            ] + Platform.allCases.flatMap(\.relinkingArguments)
            + fixture.xcframeworkDependencies.flatMap { dependency in
                [
                    "--xcframework-dependency",
                    relinkedDirectory.appendingPathComponent("\(dependency.rawValue).xcframework").path,
                ]
            }
            + fixture.relinkingArguments
        _ = try await shell.run([forgeExecutable] + arguments, logging: .disabled)
    }

    /// Runs the shared fixture validation Swift Testing bundle on the newest available iOS and watchOS simulators.
    ///
    /// Each `xcodebuild test` result is persisted and examined for duplicate-symbol linker diagnostics.
    func runSimulatorTests() async throws {
        let simulatorListOutput = try await shell.run([
            "xcrun", "simctl", "list", "devices", "available", "--json",
        ]).stdout
        let simulatorList = try JSONDecoder().decode(SimulatorList.self, from: Data(simulatorListOutput.utf8))

        for platform in SimulatorPlatform.allCases {
            let destination = try simulatorList.destination(for: platform)
            logger.notice("Running acceptance tests on \(platform.xcodeDestinationPlatform)")

            try await runClientTests(scheme: platform.testScheme, destination: destination)
        }
    }

    /// Runs one client Swift Testing scheme and persists its build-and-test log for diagnostic validation.
    func runClientTests(scheme: String, destination: String) async throws {
        let testResult = try await shell.run([
            "xcodebuild",
            "test", "-project",
            clientProjectDirectory.appendingPathComponent("AcceptanceClient.xcodeproj").path,
            "-scheme", scheme, "-configuration", "Debug",
            "-destination", destination, "-derivedDataPath", clientDerivedDataDirectory.path,
            "-test-timeouts-enabled", "YES",
            "-default-test-execution-time-allowance", "30",
            "-maximum-test-execution-time-allowance", "30",
            "CODE_SIGNING_ALLOWED=YES", "CODE_SIGN_IDENTITY=-",
        ].xcbeautified)
        try validateNoDuplicateSymbolDiagnostics(in: testResult, logFileName: "\(scheme)-build.log")
    }

    /// Persists one client build log and rejects linker diagnostics about duplicate symbols.
    ///
    /// - Parameters:
    ///   - commandResult: Captured standard output and error from one successful `xcodebuild` invocation.
    ///   - logFileName: The file name to create below the acceptance build directory.
    func validateNoDuplicateSymbolDiagnostics(
        in commandResult: CommandResult,
        logFileName: String,
    ) throws {
        let logURL = buildDirectory.appendingPathComponent(logFileName)
        let log = commandResult.stdout + commandResult.stderr
        try log.write(to: logURL, atomically: true, encoding: .utf8)

        let duplicateSymbolDiagnostic = "(?i)\\bduplicate\\s+symbols?\\b"
        if log.range(of: duplicateSymbolDiagnostic, options: [.regularExpression, .caseInsensitive]) != nil {
            throw ValidationError(
                "Client build reported duplicate-symbol diagnostics. See \(logURL.path).",
            )
        }
    }

    /// Resolves the repository root through Git so the suite is independent from the executable's location.
    static func locateRepositoryDirectory(using shell: CommandExecutor) async throws -> URL {
        let repositoryPath = try await shell.run(["git", "rev-parse", "--show-toplevel"]).stdout
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !repositoryPath.isEmpty else {
            throw ValidationError("Git did not return the DylibForge repository root.")
        }
        return URL(fileURLWithPath: repositoryPath, isDirectory: true).standardizedFileURL.resolvingSymlinksInPath()
    }

    /// The XcodeGen fixture project source directory.
    var fixturesProjectDirectory: URL {
        acceptanceDirectory.appendingPathComponent("FixturesProject", isDirectory: true)
    }

    /// The XcodeGen client project source directory.
    var clientProjectDirectory: URL {
        acceptanceDirectory.appendingPathComponent("ClientProject", isDirectory: true)
    }

    /// Per-slice `.xcarchive` output directory.
    var archivesDirectory: URL {
        buildDirectory.appendingPathComponent("Archives", isDirectory: true)
    }

    /// Returns an isolated DerivedData directory so concurrent fixture archives cannot share build state.
    func fixtureDerivedDataDirectory(for fixture: Fixture, platform: Platform) -> URL {
        buildDirectory.appendingPathComponent(
            "FixtureDerivedData/\(fixture.rawValue)-\(platform.rawValue)",
            isDirectory: true,
        )
    }

    /// Static XCFramework output directory before conversion.
    var staticDirectory: URL {
        buildDirectory.appendingPathComponent("Static", isDirectory: true)
    }

    /// Dynamic XCFramework output directory after conversion.
    var relinkedDirectory: URL {
        buildDirectory.appendingPathComponent("Relinked", isDirectory: true)
    }

    /// Derived data shared by the macOS client build and simulator test runs.
    var clientDerivedDataDirectory: URL {
        buildDirectory.appendingPathComponent("ClientDerivedData", isDirectory: true)
    }

    /// The executable produced by the generated macOS client project.
    var clientExecutable: URL {
        clientDerivedDataDirectory.appendingPathComponent(
            "Build/Products/Debug/AcceptanceClient.app/Contents/MacOS/AcceptanceClient",
        )
    }

    /// Generates an Xcode project with an explicit XcodeGen override or mise's root tool configuration.
    ///
    /// `XCODEGEN` is useful for local development; CI and normal usage resolve the pinned XcodeGen version
    /// through the root `mise.toml` file.
    func runXcodeGen(spec: URL, projectDirectory: URL) async throws {
        let arguments = ["generate", "--spec", spec.path, "--project", projectDirectory.path]

        _ = try await shell.run(["mise", "-C", repositoryDirectory.path, "exec", "--", "xcodegen"] + arguments)
    }

    /// Deletes a generated artifact only when it already exists.
    func removeIfPresent(_ url: URL) throws {
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }
}
