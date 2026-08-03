import Darwin
import Foundation

/// The subset of ANSI styling used by DylibForge: one foreground color and a reset sequence.
enum TerminalColor: String {
    /// Bright black foreground color used for low-severity diagnostics and durations.
    case brightBlack = "90"

    /// Red foreground color used for errors.
    case red = "31"

    /// Green foreground color used for successful completion and notices.
    case green = "32"

    /// Yellow foreground color used for warnings.
    case yellow = "33"

    /// Cyan foreground color used for active progress and informational alerts.
    case cyan = "36"

    /// Determines whether ANSI color is enabled for one destination stream.
    static func isEnabled(for fileDescriptor: Int32) -> Bool {
        let environment = ProcessInfo.processInfo.environment
        if let forceColor = environment["FORCE_COLOR"] {
            return forceColor != "0"
        }
        if environment["NO_COLOR"] != nil {
            return false
        }
        if environment["TERM"] == "dumb" {
            return false
        }
        return isatty(fileDescriptor) != 0
    }

    /// Determines whether a stream supports cursor-controlled live rendering.
    static func supportsLiveRendering(for fileDescriptor: Int32) -> Bool {
        isatty(fileDescriptor) != 0 && ProcessInfo.processInfo.environment["TERM"] != "dumb"
    }

    /// ANSI sequence that selects this foreground color.
    var escapeSequence: String {
        "\u{001B}[\(rawValue)m"
    }
}

extension String {
    /// Wraps the string in one ANSI foreground color and a reset sequence.
    func colored(_ color: TerminalColor) -> String {
        "\(color.escapeSequence)\(self)\u{001B}[0m"
    }

    /// Converts untrusted diagnostic content to one safe terminal line without control sequences.
    func terminalSafeLine() -> String {
        terminalSafeText().replacingOccurrences(of: "\n", with: " ")
    }

    /// Removes terminal control sequences while preserving line feeds for formatted command output.
    func terminalSafeText() -> String {
        let scalars = Array(unicodeScalars)
        var text = String.UnicodeScalarView()
        var index = 0

        while index < scalars.count {
            if scalars[index].value == 0x1B, index + 1 < scalars.count, scalars[index + 1].value == 0x5B {
                // Skip a complete ANSI CSI sequence, such as xcbeautify's color code `ESC[36;1m`.
                index += 2
                while index < scalars.count {
                    let scalar = scalars[index].value
                    index += 1
                    if (0x40 ... 0x7E).contains(scalar) {
                        break
                    }
                }
                continue
            }

            let scalar = scalars[index]
            switch scalar.value {
            // Line feeds remain structural; tabs and carriage returns become visible separators.
            case 0x0A:
                text.append("\n")
            case 0x09, 0x0D:
                text.append(" ")
            // C0 and C1 controls, including ESC, are discarded to prevent terminal control injection.
            case 0x00 ... 0x1F, 0x7F ... 0x9F:
                break
            default:
                text.append(scalar)
            }
            index += 1
        }
        return String(text)
    }
}
