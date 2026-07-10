import Foundation
import Logging
import Subprocess

final class CommandExecutor {
    private let logger = Logger(label: "dylib-forge.command")

    func run(_ arguments: String...) async throws -> CommandResult {
        try await run(arguments: arguments)
    }

    func run(arguments: [String]) async throws -> CommandResult {
        guard let executable = arguments.first else {
            throw DylibForgeError.message("Shell command is empty")
        }

        logger.info("Running command: \(displayCommand(arguments))")

        let result = try await Subprocess.run(
            .name(executable),
            arguments: Arguments(Array(arguments.dropFirst())),
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

private extension CommandExecutor {
    func displayCommand(_ arguments: [String]) -> String {
        arguments.map(quoteForDisplay).joined(separator: " ")
    }

    func quoteForDisplay(_ argument: String) -> String {
        guard !argument.isEmpty,
              argument.rangeOfCharacter(from: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"'\\"))) == nil
        else {
            let escaped = argument
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            return "\"\(escaped)\""
        }

        return argument
    }
}
