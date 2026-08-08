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

    /// ANSI sequence that selects this foreground color.
    var escapeSequence: String {
        "\u{001B}[\(rawValue)m"
    }
}

extension String {
    /// Wraps the string in one ANSI foreground color and a reset sequence.
    func colored(_ color: TerminalColor) -> String {
        let reset = "\u{001B}[0m"
        return color.escapeSequence
            + replacingOccurrences(of: "\n", with: "\(reset)\n\(color.escapeSequence)")
            + reset
    }
}
