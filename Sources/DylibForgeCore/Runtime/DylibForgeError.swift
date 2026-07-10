import Foundation

/// Shared CLI error type that surfaces human-readable messages.
enum DylibForgeError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case let .message(message):
            message
        }
    }
}
