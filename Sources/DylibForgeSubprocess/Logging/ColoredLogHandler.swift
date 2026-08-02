import Darwin
import Logging
import Synchronization

/// Writes terminal-friendly log messages while preserving plain output for redirected streams.
public final class ColoredLogHandler: LogHandler {
    private let base: Mutex<StreamLogHandler>
    private let usesColor: Bool

    private init(base: StreamLogHandler, usesColor: Bool) {
        self.base = Mutex(base)
        self.usesColor = usesColor
    }

    /// Creates a handler that writes to standard error and enables ANSI color only for a terminal.
    public static func standardError(label: String) -> ColoredLogHandler {
        ColoredLogHandler(
            base: StreamLogHandler.standardError(label: label),
            usesColor: isatty(STDERR_FILENO) != 0,
        )
    }

    /// Current minimum severity forwarded to the underlying handler.
    public var logLevel: Logger.Level {
        get { base.withLock { $0.logLevel } }
        set { base.withLock { $0.logLevel = newValue } }
    }

    /// Metadata attached to every log message.
    public var metadata: Logger.Metadata {
        get { base.withLock { $0.metadata } }
        set { base.withLock { $0.metadata = newValue } }
    }

    /// Metadata provider forwarded to the underlying handler.
    public var metadataProvider: Logger.MetadataProvider? {
        get { base.withLock { $0.metadataProvider } }
        set { base.withLock { $0.metadataProvider = newValue } }
    }

    /// Reads or updates a single metadata value.
    public subscript(metadataKey key: String) -> Logger.Metadata.Value? {
        get { base.withLock { $0[metadataKey: key] } }
        set { base.withLock { $0[metadataKey: key] = newValue } }
    }

    /// Emits a colorized message when standard error is attached to a terminal.
    public func log(event: LogEvent) {
        base.withLock { base in
            guard usesColor else {
                base.log(event: event)
                return
            }

            base.log(
                event: LogEvent(
                    level: event.level,
                    message: Logger.Message(
                        stringLiteral: coloredMessage(event.message.description, level: event.level),
                    ),
                    metadata: event.metadata,
                    source: event.source,
                    file: event.file,
                    function: event.function,
                    line: event.line,
                ),
            )
        }
    }
}

private extension ColoredLogHandler {
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
