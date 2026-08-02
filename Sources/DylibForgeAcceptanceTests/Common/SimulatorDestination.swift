import DylibForgeSubprocess
import Foundation

enum SimulatorPlatform: CaseIterable {
    case iOS
    case watchOS

    var runtimeIdentifierFragment: String {
        switch self {
        case .iOS: ".iOS-"
        case .watchOS: ".watchOS-"
        }
    }

    var xcodeDestinationPlatform: String {
        switch self {
        case .iOS: "iOS Simulator"
        case .watchOS: "watchOS Simulator"
        }
    }

    var testScheme: String {
        switch self {
        case .iOS: "AcceptanceiOSSimulatorTests"
        case .watchOS: "AcceptancewatchOSSimulatorTests"
        }
    }
}

struct SimulatorDestination: Decodable {
    let udid: String
    let isAvailable: Bool
}

struct SimulatorList: Decodable {
    let devices: [String: [SimulatorDestination]]

    func destination(for platform: SimulatorPlatform) throws -> String {
        let device = devices
            .filter { $0.key.contains(platform.runtimeIdentifierFragment) }
            .sorted { $0.key > $1.key }
            .lazy
            .flatMap(\.value)
            .first(where: \.isAvailable)

        guard let device else {
            throw AcceptanceTestError.message("No available \(platform.xcodeDestinationPlatform) device was found.")
        }
        return "platform=\(platform.xcodeDestinationPlatform),id=\(device.udid)"
    }
}

enum AcceptanceTestError: UserFacingError {
    case message(String)

    var userFacingDescription: String {
        switch self {
        case let .message(message): message
        }
    }
}
