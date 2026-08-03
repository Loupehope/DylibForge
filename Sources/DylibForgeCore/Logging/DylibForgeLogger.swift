import Darwin
import Foundation
import Synchronization

/// Displays DylibForge terminal components such as alerts and progress steps.
public final class DylibForgeLogger: Sendable {
    /// Shared configuration applied to every logger instance in the current process.
    private static let configuration = Mutex(Configuration())

    /// Renderer used to serialize this logger's terminal output with live progress steps.
    private let renderer = TerminalRenderer.shared

    /// Creates a logger that renders through the shared terminal renderer.
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

    /// Runs an asynchronous operation in one terminal progress step.
    @discardableResult
    public func progressStep<Value>(
        message: String,
        successMessage: String? = nil,
        errorMessage: String? = nil,
        operation: @escaping () async throws -> Value,
    ) async throws -> Value {
        try await ProgressStep(
            message: message,
            successMessage: successMessage,
            errorMessage: errorMessage,
            operation: operation,
        ).run()
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
}

private extension DylibForgeLogger {
    /// Mutable process-wide display settings.
    struct Configuration: Sendable {
        /// Whether informational alerts are displayed.
        var isVerbose = false
    }

    /// Renders one alert using its semantic stream and foreground color.
    func alert(_ alert: Alert, message: String) {
        let usesColor = TerminalColor.isEnabled(for: alert.fileDescriptor)
        let title = usesColor ? alert.title.colored(alert.color) : alert.title
        let normalizedMessage = alert == .error ? message.terminalSafeText() : message.terminalSafeLine()
        let messageWithContext = normalizedMessage
        let displayedMessage = if usesColor, alert == .info {
            messageWithContext.colored(.brightBlack)
        } else if usesColor, alert == .warning {
            messageWithContext.colored(.yellow)
        } else if usesColor, alert == .error {
            messageWithContext.colored(.red)
        } else {
            messageWithContext
        }
        renderer.writeLog("\(DylibForgeLogger.timestamp()) \(title) \(displayedMessage)", to: alert.output)
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

    /// Stream receiving this alert.
    var output: FileHandle {
        switch self {
        case .error: .standardError
        case .success, .warning, .info: .standardOutput
        }
    }

    /// Descriptor of the stream receiving this alert.
    var fileDescriptor: Int32 {
        switch self {
        case .error: STDERR_FILENO
        case .success, .warning, .info: STDOUT_FILENO
        }
    }

    /// Unstyled title printed before the alert body.
    var title: String {
        switch self {
        case .success: "✔︎ Success"
        case .warning: "⚠︎ Warning"
        case .error: "⨯ Error"
        case .info: "ℹ︎ Info"
        }
    }

    /// Foreground color associated with this alert.
    var color: TerminalColor {
        switch self {
        case .success: .green
        case .warning: .yellow
        case .error: .red
        case .info: .cyan
        }
    }
}
