import Foundation
import Logging
import Subprocess

/// Runs an external command and returns its standard output.
public protocol CommandExecutor: AnyObject {
    /// Runs a command represented by its executable followed by arguments.
    func run(arguments: [String]) async throws -> CommandResult
}

public extension CommandExecutor {
    /// Runs a command represented by a variadic executable-and-arguments list.
    func run(_ arguments: String...) async throws -> CommandResult {
        try await run(arguments: arguments)
    }
}

/// Runs commands using the current process environment.
public final class DefaultCommandExecutor: CommandExecutor {
    private let executor: CommandExecutorImpl

    /// Creates an executor that inherits the current process environment.
    public init(logger: Logger = Logger(label: "dylib-forge.command")) {
        executor = CommandExecutorImpl(
            developerDirectory: nil,
            logger: logger,
        )
    }

    /// Runs a command represented by its executable followed by arguments.
    public func run(arguments: [String]) async throws -> CommandResult {
        try await executor.run(arguments: arguments)
    }
}

/// Runs commands using one explicit Xcode developer directory.
public final class DeveloperCommandExecutor: CommandExecutor {
    private let executor: CommandExecutorImpl

    /// Creates an executor that sets `DEVELOPER_DIR` for every command it runs.
    public init(
        developerDirectory: String,
        logger: Logger = Logger(label: "dylib-forge.command"),
    ) {
        executor = CommandExecutorImpl(
            developerDirectory: developerDirectory,
            logger: logger,
        )
    }

    /// Runs a command represented by its executable followed by arguments.
    public func run(arguments: [String]) async throws -> CommandResult {
        try await executor.run(arguments: arguments)
    }
}

private final class CommandExecutorImpl {
    private let developerDirectory: String?
    private let logger: Logger

    init(developerDirectory: String?, logger: Logger) {
        self.developerDirectory = developerDirectory
        self.logger = logger
    }

    func run(arguments: [String]) async throws -> CommandResult {
        guard let executable = arguments.first else {
            throw DylibForgeError.message("Shell command is empty")
        }

        let result = try await Subprocess.run(
            .name(executable),
            arguments: Arguments(Array(arguments.dropFirst())),
            environment: subprocessEnvironment,
            output: .string(limit: .max),
            error: .string(limit: .max),
        )
        let stdout = result.standardOutput ?? ""
        let stderr = result.standardError ?? ""
        let trimmedStderr = stderr.trimmingCharacters(in: .whitespacesAndNewlines)

        guard result.terminationStatus.isSuccess else {
            let exitCode = switch result.terminationStatus {
            case let .exited(code):
                Int32(code)
            case let .signaled(code):
                Int32(code)
            }
            throw DylibForgeError.message(
                "Command exited with status \(exitCode): \(arguments.joined(separator: " "))\n\(stderr)",
            )
        }

        if !trimmedStderr.isEmpty {
            logger.warning("\(trimmedStderr)")
        }

        return CommandResult(stdout: stdout)
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
