import DylibForgeSubprocess

/// Errors surfaced by the XCFramework conversion command.
enum XCFrameworkError: UserFacingError {
    case message(String)

    var userFacingDescription: String {
        switch self {
        case let .message(message):
            message
        }
    }
}
