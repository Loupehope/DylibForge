import DylibForgeCore
import DylibForgeSubprocess
import Foundation

/// Discovers the SDKs exposed by the Xcode selected through `xcode-select`.
final class XCFrameworkSDKNameResolver {
    private let commandExecutor: CommandExecutor
    private let jsonDecoder: JSONDecoder

    init(
        commandExecutor: CommandExecutor,
        jsonDecoder: JSONDecoder = JSONDecoder(),
    ) {
        self.commandExecutor = commandExecutor
        self.jsonDecoder = jsonDecoder
    }

    /// Resolves SDK-scoped relinking controls from CLI sequences.
    func options(
        linkerArgs: [String],
        ignoredAutolinkDependencies: [String],
        excludedObjectNamePatterns: [String],
    ) async throws -> (
        linkerArgs: [String: [String]],
        ignoredAutolinkDependencies: [String: [String]],
        excludedObjectNamePatterns: [String: [String]],
    ) {
        let availableSDKs = try await discoverSDKs()
        return try (
            parseArguments(linkerArgs, name: "--linker-arg-sdk", sdkNames: availableSDKs),
            parseArguments(ignoredAutolinkDependencies, name: "--ignore-autolink-sdk", sdkNames: availableSDKs),
            parseArguments(excludedObjectNamePatterns, name: "--exclude-object-sdk", sdkNames: availableSDKs),
        )
    }

    /// Selects the SDK recorded by a framework bundle or matching XCFramework platform metadata.
    func sdk(for library: XCFrameworkLibrary, bundleInfo: XCFrameworkBundleInfo? = nil) throws -> String {
        if let platformName = bundleInfo?.platformName, !platformName.isEmpty {
            return platformName
        }

        guard let platform = library.supportedPlatform else {
            throw XCFrameworkError.message("AvailableLibraries item has no SupportedPlatform")
        }
        switch (platform, library.supportedPlatformVariant) {
        case ("ios", "simulator"):
            return "iphonesimulator"
        case ("ios", _):
            return "iphoneos"
        case ("tvos", "simulator"):
            return "appletvsimulator"
        case ("tvos", _):
            return "appletvos"
        case ("watchos", "simulator"):
            return "watchsimulator"
        case ("watchos", _):
            return "watchos"
        case ("xros", "simulator"), ("visionos", "simulator"):
            return "xrsimulator"
        case ("xros", _), ("visionos", _):
            return "xros"
        case ("macos", _):
            return "macosx"
        default:
            let variant = library.supportedPlatformVariant.map { " (\($0))" } ?? ""
            throw XCFrameworkError.message("Unsupported XCFramework platform: \(platform)\(variant)")
        }
    }
}

private extension XCFrameworkSDKNameResolver {
    func discoverSDKs() async throws -> Set<String> {
        let output = try await commandExecutor.run(["xcodebuild", "-showsdks", "-json"]).stdout
        let xcodeSDKs = try jsonDecoder.decode([XcodeSDK].self, from: Data(output.utf8))
        let sdkNames = Set(xcodeSDKs.map(\.platform))

        guard !sdkNames.isEmpty else {
            throw XCFrameworkError.message("xcodebuild -showsdks returned no SDK names")
        }
        return sdkNames
    }

    func parseArguments(_ values: [String], name: String, sdkNames: Set<String>) throws -> [String: [String]] {
        var currentSDK: String?
        var result: [String: [String]] = [:]

        for value in values {
            if value == "any" || sdkNames.contains(value) {
                currentSDK = value
                continue
            }
            guard let currentSDK else {
                throw XCFrameworkError.message("\(name) must start with any or an SDK name, such as iphoneos")
            }
            result[currentSDK, default: []].append(value)
        }
        return result
    }
}

/// The subset of `xcodebuild -showsdks -json` used to select an XCFramework SDK.
private struct XcodeSDK: Decodable {
    let platform: String
}
