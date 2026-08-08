import Darwin
import Foundation
import Synchronization

/// Displays DylibForge terminal components such as alerts and progress steps.
public final class DylibForgeLogger: Sendable {
    /// Shared configuration applied to every logger instance in the current process.
    private static let configuration = Mutex(Configuration())

    /// Serializes complete log entries emitted by concurrent operations.
    private static let output = Mutex(())

    /// Creates a logger.
    public init() {}

    /// Enables or disables informational alerts for the current process.
    public static func configure(verbose: Bool) {
        configuration.withLock { $0.isVerbose = verbose }
    }

    /// Displays a successful outcome alert.
    public func success(_ message: String) {
        alert(.success, message: message)
    }

    /// Displays a warning alert.
    public func warning(_ message: String) {
        alert(.warning, message: message)
    }

    /// Displays an error alert.
    public func error(_ message: String) {
        alert(.error, message: message)
    }

    /// Displays an informational alert.
    public func info(_ message: String) {
        guard Self.configuration.withLock(\.isVerbose) else { return }
        alert(.info, message: message)
    }

    /// Runs an asynchronous operation and reports its outcome.
    public func progressStep(
        message: String,
        successMessage: String,
        operation: @escaping () async throws -> Void,
    ) async throws {
        alert(.inProgress, message: message)

        let duration = try await ContinuousClock().measure {
            try await operation()
        }

        success("\(successMessage) [\(elapsedTime(duration))]")
    }

    /// Formats the current local date and time without fractional seconds or a time-zone suffix.
    static func timestamp() -> String {
        var seconds = time_t(Date().timeIntervalSince1970)
        var localTime = tm()
        localtime_r(&seconds, &localTime)

        var buffer = [CChar](repeating: 0, count: 20)
        let length = strftime(&buffer, buffer.count, "%Y-%m-%d %H:%M:%S", &localTime)
        return String(decoding: buffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    /// Formats a progress-step duration.
    private func elapsedTime(_ duration: Duration) -> String {
        let seconds = Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
        return String(format: "%.1fs", seconds)
    }
}

private extension DylibForgeLogger {
    /// Mutable process-wide display settings.
    struct Configuration: Sendable {
        /// Whether informational alerts are displayed.
        var isVerbose = false
    }

    /// Renders one alert using its semantic stream and foreground color.
    func alert(_ alert: Alert, message: String) {
        var title = alert.title
        var displayedMessage = message

        switch alert {
        case .success:
            title = title.colored(.green)
            displayedMessage = displayedMessage.colored(.green)
        case .warning:
            title = title.colored(.yellow)
            displayedMessage = displayedMessage.colored(.yellow)
        case .error:
            title = title.colored(.red)
            displayedMessage = displayedMessage.colored(.red)
        case .info:
            title = title.colored(.cyan)
            displayedMessage = displayedMessage.colored(.brightBlack)
        case .inProgress:
            title = title.colored(.cyan)
            displayedMessage = displayedMessage.colored(.cyan)
        }

        let entry = Data("\(DylibForgeLogger.timestamp()) \(title) \(displayedMessage)\n".utf8)
        Self.output.withLock { _ in
            alert.output.write(entry)
        }
    }
}

/// Semantic terminal alerts supported by DylibForge.
private enum Alert: Equatable {
    /// Confirms that an operation completed successfully.
    case success

    /// Reports a non-fatal condition that needs attention.
    case warning

    /// Reports a failed operation.
    case error

    /// Reports contextual information.
    case info

    /// Indicates that an operation has started.
    case inProgress

    /// Stream receiving this alert.
    var output: FileHandle {
        switch self {
        case .error: .standardError
        case .success, .warning, .info, .inProgress: .standardOutput
        }
    }

    /// Unstyled title printed before the alert body.
    var title: String {
        switch self {
        case .success: "✔︎"
        case .warning: "⚠︎"
        case .error: "⨯"
        case .info: "ℹ︎"
        case .inProgress: "↻"
        }
    }
}
