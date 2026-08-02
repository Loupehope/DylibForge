import Foundation

/// Shared CLI error type that surfaces human-readable messages.
public enum DylibForgeError: LocalizedError {
    case message(String)

    public var errorDescription: String? {
        switch self {
        case let .message(message):
            message
        }
    }
}
