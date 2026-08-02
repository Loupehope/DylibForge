/// An error that provides text suitable for command-line output.
public protocol UserFacingError: Error {
    /// The message displayed to the command-line user.
    var userFacingDescription: String { get }
}

/// Formats errors for command-line output.
public enum ErrorPresenter {
    /// Returns an explicit user-facing message, or a textual fallback for external errors.
    public static func message(for error: Error) -> String {
        if let error = error as? any UserFacingError {
            return error.userFacingDescription
        }
        return String(describing: error)
    }
}

/// Shared CLI error type that surfaces human-readable messages.
public enum DylibForgeError: UserFacingError {
    case message(String)

    public var userFacingDescription: String {
        switch self {
        case let .message(message):
            message
        }
    }
}
