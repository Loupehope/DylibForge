import DylibForgeCore
import Foundation

enum SimulatorPlatform: CaseIterable, Sendable {
    case iOS
    case watchOS

    /// The runtime identifier prefix used by CoreSimulator for this platform.
    var runtimeIdentifierPrefix: String {
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

    /// SDK name accepted by `xcrun --sdk` when resolving the Xcode-supported runtime version.
    var simulatorSDK: String {
        switch self {
        case .iOS: "iphonesimulator"
        case .watchOS: "watchsimulator"
        }
    }

    var testScheme: String {
        switch self {
        case .iOS: "AcceptanceiOSSimulatorTests"
        case .watchOS: "AcceptancewatchOSSimulatorTests"
        }
    }

    func supports(_ device: SimulatorDestination) -> Bool {
        switch self {
        case .iOS:
            device.isPhone
        case .watchOS:
            device.isWatch
        }
    }
}

struct SimulatorDestination: Decodable, Sendable {
    let udid: String
    let isAvailable: Bool
    let deviceTypeIdentifier: String

    var isPhone: Bool {
        deviceTypeIdentifier.contains(".iPhone-")
    }

    var isWatch: Bool {
        deviceTypeIdentifier.contains(".Apple-Watch-")
    }
}

struct SimulatorList: Decodable, Sendable {
    let devices: [String: [SimulatorDestination]]

    /// Returns an available device in the deployment-target-to-SDK version range.
    func device(
        for platform: SimulatorPlatform,
        minimumDeploymentTarget: String,
        maximumSDKPlatformVersion: String,
    ) throws -> SimulatorDestination {
        let device = devices.compactMap { runtimeIdentifier, devices -> (version: String, device: SimulatorDestination)? in
            guard let range = runtimeIdentifier.range(of: platform.runtimeIdentifierPrefix) else {
                return nil
            }
            let runtimeVersion = String(runtimeIdentifier[range.upperBound...]).replacingOccurrences(of: "-", with: ".")
            guard
                runtimeVersion.compare(minimumDeploymentTarget, options: .numeric) != .orderedAscending,
                runtimeVersion.compare(maximumSDKPlatformVersion, options: .numeric) != .orderedDescending,
                let device = devices.first(where: { $0.isAvailable && platform.supports($0) })
            else { return nil }
            return (runtimeVersion, device)
        }
        .max { $0.version.compare($1.version, options: .numeric) == .orderedAscending }?.device

        guard let device else {
            throw DylibForgeError.message(
                "No available \(platform.xcodeDestinationPlatform) device was found between deployment target \(minimumDeploymentTarget) and Xcode SDK \(maximumSDKPlatformVersion).",
            )
        }
        return device
    }
}
