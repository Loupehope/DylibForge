import Darwin
import Foundation
import Logging
import Synchronization

/// Writes terminal-friendly log messages while preserving plain output for redirected streams.
public final class ColoredLogHandler: LogHandler {
    private let dateFormatter: DateFormatter = {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = .current
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return dateFormatter
    }()

    private let state: Mutex<State>
    private let output: FileHandle
    private let usesColor: Bool

    private init(output: FileHandle, usesColor: Bool) {
        state = Mutex(State())
        self.output = output
        self.usesColor = usesColor
    }

    /// Creates a handler that writes messages to standard error and enables ANSI color only for a terminal.
    ///
    /// The label is intentionally omitted from the output: acceptance logs are easier to scan when they
    /// contain the action rather than the logger's transport metadata.
    public static func standardError(label _: String) -> ColoredLogHandler {
        ColoredLogHandler(
            output: .standardError,
            usesColor: isatty(STDERR_FILENO) != 0,
        )
    }

    /// Current minimum severity forwarded to the underlying handler.
    public var logLevel: Logger.Level {
        get { state.withLock { $0.logLevel } }
        set { state.withLock { $0.logLevel = newValue } }
    }

    /// Metadata attached to every log message.
    public var metadata: Logger.Metadata {
        get { state.withLock { $0.metadata } }
        set { state.withLock { $0.metadata = newValue } }
    }

    /// Metadata provider forwarded to the underlying handler.
    public var metadataProvider: Logger.MetadataProvider? {
        get { state.withLock { $0.metadataProvider } }
        set { state.withLock { $0.metadataProvider = newValue } }
    }

    /// Reads or updates a single metadata value.
    public subscript(metadataKey key: String) -> Logger.Metadata.Value? {
        get { state.withLock { $0.metadata[key] } }
        set { state.withLock { $0.metadata[key] = newValue } }
    }

    /// Emits a colorized message when standard error is attached to a terminal.
    public func log(event: LogEvent) {
        state.withLock { _ in
            let message = event.message.description
            let output = usesColor ? coloredMessage(message, level: event.level) : message
            let timestamp = dateFormatter.string(from: Date())
            self.output.write(Data("\(timestamp) \(output)\n".utf8))
        }
    }
}

private extension ColoredLogHandler {
    struct State: Sendable {
        var logLevel: Logger.Level = .info
        var metadata = Logger.Metadata()
        var metadataProvider: Logger.MetadataProvider?
    }

    /// ANSI foreground color for each log severity.
    func colorCode(for level: Logger.Level) -> String {
        switch level {
        case .trace, .debug, .info:
            "\u{001B}[90m"
        case .notice:
            "\u{001B}[32m"
        case .warning:
            "\u{001B}[33m"
        case .error:
            "\u{001B}[31m"
        case .critical:
            "\u{001B}[1;31m"
        }
    }

    /// Colors each line independently so multi-line linker diagnostics do not leak terminal state.
    func coloredMessage(_ message: String, level: Logger.Level) -> String {
        let color = colorCode(for: level)
        return
            message
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map { "\(color)\($0)\u{001B}[0m" }
                .joined(separator: "\n")
    }
}
