import DylibForgeCore
import Foundation

/// Minimum operating-system versions shared by acceptance fixtures, the validation client, and relinked binaries.
struct DeploymentTargets: Decodable, Sendable {
    /// The minimum version for macOS binaries.
    let macOS: String

    /// The minimum version for iOS device and simulator binaries.
    let iOS: String

    /// The minimum version for watchOS device and simulator binaries.
    let watchOS: String
}

/// Minimum operating-system versions shared by acceptance fixtures, the validation client, and relinked binaries.
final class DeploymentTargetsProvider: Decodable, Sendable {
    private let deploymentTargets: DeploymentTargets

    /// Loads and validates the shared acceptance deployment-target configuration.
    ///
    /// - Parameters:
    ///   - fileURL: Location of the JSON configuration file.
    ///   - fileManager: File-system dependency used to read the configuration.
    init(fileURL: URL, fileManager: FileManager) throws {
        do {
            guard let data = fileManager.contents(atPath: fileURL.path) else {
                throw DylibForgeError.message("Could not read deployment targets from \(fileURL.path).")
            }
            deploymentTargets = try JSONDecoder().decode(DeploymentTargets.self, from: data)
        } catch let error as DylibForgeError {
            throw error
        } catch {
            throw DylibForgeError.message(
                "Could not read deployment targets from \(fileURL.path): \(error.localizedDescription)",
            )
        }
    }

    /// Environment variables expanded by the two XcodeGen project specifications.
    var xcodeGenEnvironment: [String: String] {
        [
            "XCODEGEN_MACOS_DEPLOYMENT_TARGET": deploymentTargets.macOS,
            "XCODEGEN_IOS_DEPLOYMENT_TARGET": deploymentTargets.iOS,
            "XCODEGEN_WATCHOS_DEPLOYMENT_TARGET": deploymentTargets.watchOS,
        ]
    }

    /// SDK-qualified arguments that give `dylib-forge xc` the same minimum versions as the Xcode projects.
    var linkerArguments: [String] {
        linkerArguments(sdk: "macosx", flag: "-mmacosx-version-min=", version: deploymentTargets.macOS)
            + linkerArguments(sdk: "iphoneos", flag: "-miphoneos-version-min=", version: deploymentTargets.iOS)
            + linkerArguments(sdk: "iphonesimulator", flag: "-mios-simulator-version-min=", version: deploymentTargets.iOS)
            + linkerArguments(sdk: "watchos", flag: "-mwatchos-version-min=", version: deploymentTargets.watchOS)
            + linkerArguments(sdk: "watchsimulator", flag: "-mwatchos-simulator-version-min=", version: deploymentTargets.watchOS)
    }

    /// The configured minimum version for a simulator platform.
    func minimumVersion(for platform: SimulatorPlatform) -> String {
        switch platform {
        case .iOS: deploymentTargets.iOS
        case .watchOS: deploymentTargets.watchOS
        }
    }
}

private extension DeploymentTargetsProvider {
    /// Builds one SDK-specific `dylib-forge xc` linker-argument pair.
    func linkerArguments(sdk: String, flag: String, version: String) -> [String] {
        ["--linker-arg-sdk", sdk, "--linker-arg-sdk", "\(flag)\(version)"]
    }
}
