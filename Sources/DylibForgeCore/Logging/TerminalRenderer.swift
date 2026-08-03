import Darwin
import Foundation
import Synchronization

/// Serializes terminal output around one live progress line.
final class TerminalRenderer: Sendable {
    /// Shared renderer used by progress steps and alerts.
    static let shared = TerminalRenderer()

    /// Protects the live progress line and all writes that redraw it.
    private let state = Mutex(State())

    /// Prevents separate renderer instances from competing for one terminal.
    private init() {}

    /// Registers the current progress step and returns its renderer identifier.
    func beginProgress() -> UUID {
        state.withLock { state in
            let identifier = UUID()
            state.progress = Progress(identifier: identifier, content: "")
            return identifier
        }
    }

    /// Replaces the current spinner frame and redraws its one terminal line.
    func renderProgress(_ identifier: UUID, content: String) {
        state.withLock { state in
            guard state.progress?.identifier == identifier else { return }
            eraseLiveLine(&state)
            state.progress?.content = content
            drawLiveLine(&state)
        }
    }

    /// Removes the current progress step and emits its final result.
    func finishProgress(_ identifier: UUID, content: String, to output: FileHandle) {
        state.withLock { state in
            guard state.progress?.identifier == identifier else { return }
            eraseLiveLine(&state)
            state.progress = nil
            write("\(content)\n", to: output)
        }
    }

    /// Removes a cancelled progress step without emitting a completion line.
    func cancelProgress(_ identifier: UUID) {
        state.withLock { state in
            guard state.progress?.identifier == identifier else { return }
            eraseLiveLine(&state)
            state.progress = nil
        }
    }

    /// Emits an alert above the live progress line without corrupting its animation.
    func writeLog(_ content: String, to output: FileHandle) {
        state.withLock { state in
            eraseLiveLine(&state)
            write("\(content)\n", to: output)
            drawLiveLine(&state)
        }
    }

    /// Writes a non-interactive line without interleaving concurrent file-handle writes.
    func writePlain(_ content: String, to output: FileHandle) {
        state.withLock { _ in
            write(content, to: output)
        }
    }
}

private extension TerminalRenderer {
    /// ANSI sequences used for one-line redraws and fallback terminal dimensions.
    enum TerminalLayout {
        /// Typical terminal width used when `ioctl` cannot report a terminal size.
        static let fallbackColumns = 80

        /// Carriage return followed by ANSI EL 2, which clears the current terminal row.
        static let clearCurrentLine = "\r\u{001B}[2K"
    }

    /// Mutable state for the one current progress step.
    struct State: Sendable {
        /// Current progress step, if an operation is running.
        var progress: Progress?

        /// Terminal width used when drawing the live line.
        var renderedColumns: Int?
    }

    /// One active progress step.
    struct Progress: Sendable {
        /// Renderer identifier associated with this step.
        let identifier: UUID

        /// ANSI-decorated text rendered without a trailing newline.
        var content: String
    }

    /// Clears the live line, or starts a new one when resizing made relative clearing unsafe.
    func eraseLiveLine(_ state: inout State) {
        guard state.renderedColumns != nil else { return }
        guard state.renderedColumns == terminalColumns else {
            // A previously one-line message may have reflowed after resize, so preserve it and continue below it.
            write("\n", to: .standardOutput)
            state.renderedColumns = nil
            return
        }
        write(TerminalLayout.clearCurrentLine + "\r", to: .standardOutput)
        state.renderedColumns = nil
    }

    /// Draws the current spinner frame as one line that cannot wrap at the current width.
    func drawLiveLine(_ state: inout State) {
        guard let content = state.progress?.content, !content.isEmpty else { return }
        let columns = terminalColumns
        write("\(TerminalLayout.clearCurrentLine)\(oneLine(content, columns: columns))", to: .standardOutput)
        state.renderedColumns = columns
    }

    /// Returns a line that fits one terminal row, reserving the final column to avoid automatic wrapping.
    func oneLine(_ text: String, columns: Int) -> String {
        let maximumWidth = max(1, columns - 1)
        let plainText = stripANSISequences(from: text)
        guard displayWidth(of: plainText) > maximumWidth else { return text }
        return truncate(plainText, to: maximumWidth)
    }

    /// Current terminal width, with a conservative fallback for redirected or unknown output.
    var terminalColumns: Int {
        var windowSize = winsize()
        guard ioctl(STDOUT_FILENO, TIOCGWINSZ, &windowSize) == 0, windowSize.ws_col > 0 else {
            return TerminalLayout.fallbackColumns
        }
        return Int(windowSize.ws_col)
    }

    /// Removes ANSI CSI sequences so styling bytes do not contribute to display width.
    func stripANSISequences(from text: String) -> String {
        let scalars = Array(text.unicodeScalars)
        var result = String.UnicodeScalarView()
        var index = 0
        while index < scalars.count {
            guard scalars[index].value == 0x1B, index + 1 < scalars.count, scalars[index + 1].value == 0x5B else {
                result.append(scalars[index])
                index += 1
                continue
            }
            index += 2
            while index < scalars.count {
                let scalar = scalars[index].value
                index += 1
                if (0x40 ... 0x7E).contains(scalar) {
                    break
                }
            }
        }
        return String(result)
    }

    /// Measures Unicode scalar cell widths using the platform terminal-width implementation.
    func displayWidth(of text: String) -> Int {
        text.unicodeScalars.reduce(into: 0) { width, scalar in
            width += max(0, Int(wcwidth(wchar_t(scalar.value))))
        }
    }

    /// Shortens plain text to a requested terminal width while retaining a visible ellipsis.
    func truncate(_ text: String, to maximumWidth: Int) -> String {
        guard displayWidth(of: text) > maximumWidth else { return text }
        let ellipsis = "…"
        let textWidth = max(0, maximumWidth - displayWidth(of: ellipsis))
        var result = ""
        var width = 0
        for character in text {
            let characterWidth = displayWidth(of: String(character))
            guard width + characterWidth <= textWidth else { break }
            result.append(character)
            width += characterWidth
        }
        return result + ellipsis
    }

    /// Writes UTF-8 terminal content without adding a newline.
    func write(_ content: String, to output: FileHandle) {
        output.write(Data(content.utf8))
    }
}
