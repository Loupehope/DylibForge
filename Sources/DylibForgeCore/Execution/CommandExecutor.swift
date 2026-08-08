import Foundation
import Subprocess
import System

/// Runs an external command and returns its standard output.
public protocol CommandExecutor: AnyObject, Sendable {
    /// Runs a command represented by its executable followed by arguments.
    func run(_ arguments: [String]) async throws -> CommandResult
}

public extension [String] {
    /// Wraps an `xcodebuild` command with xcbeautify while preserving the xcodebuild exit status.
    ///
    /// `NSUnbufferedIO` and standard-error redirection let xcbeautify render concurrent Xcode output in order.
    /// The Z shell's `pipefail` option ensures an Xcode failure is not hidden by a successful formatter process.
    var xcbeautified: Self {
        let command = map { "'\($0.replacingOccurrences(of: "'", with: "'\\\"'\\\"'"))'" }
            .joined(separator: " ")
        let script = "set -o pipefail\nNSUnbufferedIO=YES \(command) 2>&1 | xcbeautify"
        return ["zsh", "-c", script]
    }
}

/// Runs commands using the current process environment.
public final class DefaultCommandExecutor: CommandExecutor {
    private let executor: CommandExecutorImpl

    /// Creates an executor that inherits the current process environment.
    public init(logger: DylibForgeLogger = DylibForgeLogger()) {
        executor = CommandExecutorImpl(
            developerDirectory: nil,
            logger: logger,
        )
    }

    /// Runs a command represented by its executable followed by arguments.
    public func run(_ arguments: [String]) async throws -> CommandResult {
        try await executor.run(arguments)
    }
}

/// Runs commands using one explicit Xcode developer directory.
public final class DeveloperCommandExecutor: CommandExecutor {
    private let executor: CommandExecutorImpl

    /// Creates an executor that sets `DEVELOPER_DIR` for every command it runs.
    public init(
        developerDirectory: String,
        logger: DylibForgeLogger = DylibForgeLogger(),
    ) {
        executor = CommandExecutorImpl(
            developerDirectory: developerDirectory,
            logger: logger,
        )
    }

    /// Runs a command represented by its executable followed by arguments.
    public func run(_ arguments: [String]) async throws -> CommandResult {
        try await executor.run(arguments)
    }
}

private final class CommandExecutorImpl: Sendable {
    private let developerDirectory: String?
    private let logger: DylibForgeLogger

    init(developerDirectory: String?, logger: DylibForgeLogger) {
        self.developerDirectory = developerDirectory
        self.logger = logger
    }

    func run(_ arguments: [String]) async throws -> CommandResult {
        guard let executable = arguments.first else {
            throw DylibForgeError.message("Shell command is empty")
        }

        logger.info("Running command: \(arguments.joined(separator: " "))")

        let executableConfiguration: Executable = executable.contains("/")
            ? .path(FilePath(executable))
            : .name(executable)
        let result = try await Subprocess.run(
            executableConfiguration,
            arguments: Arguments(Array(arguments.dropFirst())),
            environment: subprocessEnvironment,
            output: .string(limit: .max),
            error: .string(limit: .max),
        )
        let stdout = result.standardOutput
        let stderr = result.standardError
        let trimmedStderr = stderr.trimmingCharacters(in: .whitespacesAndNewlines)

        guard result.terminationStatus.isSuccess else {
            let exitCode = switch result.terminationStatus {
            case let .exited(code):
                Int32(code)
            case let .signaled(code):
                Int32(code)
            }
            let commandOutput = [stdout, stderr]
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
            throw DylibForgeError.message(
                "Command exited with status \(exitCode): \(arguments.joined(separator: " "))\n\(commandOutput)",
            )
        }

        if !trimmedStderr.isEmpty {
            logger.warning("\(trimmedStderr)")
        }

        return CommandResult(stdout: stdout, stderr: stderr)
    }
}

private extension CommandExecutorImpl {
    var subprocessEnvironment: Environment {
        guard let developerDirectory else {
            return .inherit
        }

        return .inherit.updating(["DEVELOPER_DIR": developerDirectory])
    }
}
