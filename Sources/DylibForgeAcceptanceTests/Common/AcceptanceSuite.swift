import ArgumentParser
import DylibForgeCore
import Foundation

/// Runs the acceptance pipeline from generated fixture source through client runtime validation.
///
/// The suite creates static XCFrameworks for every fixture and supported platform, converts them to
/// dynamic XCFrameworks, then verifies that a client can link and execute them on macOS, iOS Simulator,
/// and watchOS Simulator.
final class AcceptanceSuite: Sendable {
    private let acceptanceDirectory: URL
    private let repositoryDirectory: URL
    private let buildDirectory: URL
    private let deploymentTargetsProvider: DeploymentTargetsProvider
    private let logger: DylibForgeLogger
    private let shell: CommandExecutor
    private let developerDirectory: String

    private nonisolated(unsafe) let fileManager = FileManager.default

    /// Locates the repository and prepares a shared executor configured for the selected Xcode.
    ///
    /// - Parameter xcodePath: An optional Xcode developer directory; the current `xcode-select` value is
    ///   used when this is `nil`.
    init(xcodePath: String?) async throws {
        logger = DylibForgeLogger()
        repositoryDirectory = try await Self.locateRepositoryDirectory(using: DefaultCommandExecutor(logger: logger))
        acceptanceDirectory = repositoryDirectory.appendingPathComponent("AcceptanceTests", isDirectory: true)
        buildDirectory = acceptanceDirectory.appendingPathComponent(".build", isDirectory: true)
        deploymentTargetsProvider = try DeploymentTargetsProvider(
            fileURL: acceptanceDirectory.appendingPathComponent("deployment-targets.json"),
            fileManager: fileManager,
        )
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

    /// Builds the `dylib-forge` executable consumed by the relinking stage.
    func buildDylibForge() async throws {
        _ = try await shell.run([
            "swift", "build", "--package-path", repositoryDirectory.path, "--product", "dylib-forge",
        ])
    }

    /// Generates the fixtures Xcode project and builds every platform slice.
    ///
    /// Builds each fixture and combines its platform slices into one static XCFramework used by relinking.
    func buildFixtures() async throws {
        try await runXcodeGen(
            spec: fixturesProjectDirectory.appendingPathComponent("project.yml"),
            projectDirectory: fixturesProjectDirectory,
        )

        for stage in try fixtureStages() {
            try await stage.concurrentForEach { [weak self] fixture in
                guard let self else { return }
                let frameworkURLs = try await archiveFrameworks(for: fixture)

                let outputURL = staticDirectory.appendingPathComponent("\(fixture.rawValue).xcframework")
                try removeIfPresent(outputURL)
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
    }

    /// Relinks each static fixture XCFramework with the locally built DylibForge executable.
    ///
    /// Fixtures run in dependency stages: every fixture in a stage has all of its relinked XCFramework
    /// dependencies produced by earlier stages.
    func relinkFixtures() async throws {
        try fileManager.createDirectory(at: relinkedDirectory, withIntermediateDirectories: true)
        let forgeExecutable = repositoryDirectory.appendingPathComponent(".build/debug/dylib-forge").path

        guard fileManager.isExecutableFile(atPath: forgeExecutable) else {
            throw ValidationError(
                "dylib-forge is missing: \(forgeExecutable). Run the `run` command or build it first.",
            )
        }

        for stage in try fixtureStages() {
            try await stage.concurrentForEach { [weak self] fixture in
                guard let self else { return }
                try await relink(fixture, using: forgeExecutable)
            }
        }
    }

    /// Runs generated Swift Testing bundles and rejects duplicate-symbol diagnostics in every build log.
    func buildAndRunClient() async throws {
        try await runXcodeGen(
            spec: clientProjectDirectory.appendingPathComponent("project.yml"),
            projectDirectory: clientProjectDirectory,
        )
        let simulatorTestConfigurations = try await simulatorTestConfigurations()
        for configuration in simulatorTestConfigurations {
            _ = try await shell.run(["xcrun", "simctl", "bootstatus", configuration.udid, "-b"])
        }
        let testConfigurations = [
            (scheme: "AcceptanceMacOSTests", destination: "platform=macOS,arch=arm64"),
        ] + simulatorTestConfigurations.map { (scheme: $0.scheme, destination: $0.destination) }
        try await testConfigurations.concurrentForEach { [weak self] configuration in
            guard let self else { return }
            try await runClientTests(scheme: configuration.scheme, destination: configuration.destination)
        }
    }
}

private extension AcceptanceSuite {
    /// Splits fixtures into topological dependency stages for building and relinking.
    func fixtureStages() throws -> [[Fixture]] {
        var remainingFixtures = Fixture.allCases
        var completedFixtureNames = Set<String>()
        var stages: [[Fixture]] = []

        while !remainingFixtures.isEmpty {
            let stage = remainingFixtures.filter { fixture in
                fixture.xcframeworkDependencies.allSatisfy { dependency in
                    completedFixtureNames.contains(dependency.rawValue)
                }
            }

            guard !stage.isEmpty else {
                let unresolvedFixtures = remainingFixtures.map(\.rawValue).joined(separator: ", ")
                throw ValidationError(
                    "Could not resolve fixture dependencies. Remaining fixtures: \(unresolvedFixtures).",
                )
            }

            stages.append(stage)
            completedFixtureNames.formUnion(stage.map(\.rawValue))
            let stageNames = Set(stage.map(\.rawValue))
            remainingFixtures.removeAll { stageNames.contains($0.rawValue) }
        }

        return stages
    }

    /// Archives every device and simulator slice for one fixture and returns framework URLs in platform order.
    ///
    /// Runs slices in order because the enclosing fixture map already limits active Xcode builds by CPU count.
    func archiveFrameworks(for fixture: Fixture) async throws -> [URL] {
        var frameworkURLs: [URL] = []
        for platform in Platform.allCases {
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
            frameworkURLs.append(archiveURL.appendingPathComponent(fixture.archiveProduct.path(for: fixture)))
        }
        return frameworkURLs
    }

    /// Converts one static fixture XCFramework and supplies its already-converted XCFramework dependencies.
    func relink(_ fixture: Fixture, using forgeExecutable: String) async throws {
        let inputURL = staticDirectory.appendingPathComponent("\(fixture.rawValue).xcframework")
        let outputURL = relinkedDirectory.appendingPathComponent("\(fixture.rawValue).xcframework")
        try removeIfPresent(outputURL)
        let arguments =
            [
                "xc",
                inputURL.path,
                "--output", outputURL.path,
                "--xcode-path", developerDirectory,
            ] + fixture.xcframeworkDependencies.flatMap { dependency in
                [
                    "--xcframework-dependency",
                    relinkedDirectory.appendingPathComponent("\(dependency.rawValue).xcframework").path,
                ]
            }
            + deploymentTargetsProvider.linkerArguments
            + fixture.relinkingArguments
        _ = try await shell.run([forgeExecutable] + arguments)
    }

    /// Resolves the newest iOS and watchOS simulator destinations supported by the selected Xcode SDKs.
    ///
    /// The returned UDIDs allow the caller to finish booting the selected simulators before running their
    /// test schemes in parallel.
    func simulatorTestConfigurations() async throws -> [(scheme: String, destination: String, udid: String)] {
        let simulatorListOutput = try await shell.run([
            "xcrun", "simctl", "list", "devices", "available", "--json",
        ]).stdout
        let simulatorList = try JSONDecoder().decode(SimulatorList.self, from: Data(simulatorListOutput.utf8))

        var configurations: [(scheme: String, destination: String, udid: String)] = []
        for platform in SimulatorPlatform.allCases {
            let sdkPlatformVersion = try await shell.run([
                "xcrun", "--sdk", platform.simulatorSDK, "--show-sdk-platform-version",
            ]).stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            let device = try simulatorList.device(
                for: platform,
                minimumDeploymentTarget: deploymentTargetsProvider.minimumVersion(for: platform),
                maximumSDKPlatformVersion: sdkPlatformVersion,
            )
            configurations.append((
                scheme: platform.testScheme,
                destination: "platform=\(platform.xcodeDestinationPlatform),id=\(device.udid)",
                udid: device.udid,
            ))
        }
        return configurations
    }

    /// Runs one client Swift Testing scheme and persists its build-and-test log for diagnostic validation.
    func runClientTests(scheme: String, destination: String) async throws {
        let testResult = try await shell.run([
            "xcodebuild",
            "test", "-project",
            clientProjectDirectory.appendingPathComponent("AcceptanceClient.xcodeproj").path,
            "-scheme", scheme, "-configuration", "Debug",
            "-destination", destination, "-derivedDataPath", clientDerivedDataDirectory(for: scheme).path,
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

    /// Returns an isolated DerivedData directory for one fixture archive.
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

    /// Returns the DerivedData directory for one test scheme.
    func clientDerivedDataDirectory(for scheme: String) -> URL {
        buildDirectory.appendingPathComponent("ClientDerivedData/\(scheme)", isDirectory: true)
    }

    /// Generates an Xcode project with shared deployment targets and mise's root XcodeGen configuration.
    ///
    /// `XCODEGEN` is useful for local development; CI and normal usage resolve the pinned XcodeGen version
    /// through the root `mise.toml` file.
    func runXcodeGen(spec: URL, projectDirectory: URL) async throws {
        let environmentAssignments = deploymentTargetsProvider.xcodeGenEnvironment
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
        let arguments = ["generate", "--spec", spec.path, "--project", projectDirectory.path]

        _ = try await shell.run(
            ["env"] + environmentAssignments + ["mise", "-C", repositoryDirectory.path, "exec", "--", "xcodegen"] + arguments,
        )
    }

    /// Deletes a generated artifact only when it already exists.
    func removeIfPresent(_ url: URL) throws {
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }
}
