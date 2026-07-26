import Foundation

/// Errors surfaced by the XCFramework conversion command.
enum XCFrameworkError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case let .message(message):
            message
        }
    }
}
