import Foundation
import Logging

/// Drives architecture discovery, autolink extraction, and the final `clang -dynamiclib` invocation.
final class ClangLinker {
    private let environment: ToolEnvironment
    private let machoEditor: MachOEditor
    private let directiveParser: AutolinkDirectiveParser
    private let frameworkFilter: AutolinkFrameworkFilter

    /// Wires linker dependencies around the shared runtime environment and Mach-O editor.
    init(
        environment: ToolEnvironment,
        machoEditor: MachOEditor,
        directiveParser: AutolinkDirectiveParser = AutolinkDirectiveParser(),
        frameworkFilter: AutolinkFrameworkFilter = AutolinkFrameworkFilter(),
    ) {
        self.environment = environment
        self.machoEditor = machoEditor
        self.directiveParser = directiveParser
        self.frameworkFilter = frameworkFilter
    }

    /// Returns the architecture list and fat/universal-file flag.
    func detectArchitectures(in binaryURL: URL) async throws -> ArchitectureSlices {
        let architecturesResult = try await environment.shell.run("lipo", "-archs", binaryURL.path)
        let infoResult = try await environment.shell.run("lipo", "-info", binaryURL.path)
        let architectures = architecturesResult.stdout.split(whereSeparator: { $0.isWhitespace }).map(String.init)

        guard !architectures.isEmpty else {
            throw DylibForgeError.message("Unable to determine architectures for file: \(binaryURL.path)")
        }

        return ArchitectureSlices(
            architectures: architectures,
            isUniversal: !infoResult.stdout.contains("Non-fat file:"),
        )
    }

    /// Extracts linker options from object files.
    func extractAutolinkDirectives(from objectFiles: [URL]) throws -> AutolinkDirectives {
        var tokens: [String] = []

        for objectURL in objectFiles {
            let bytes = try environment.files.readFile(at: objectURL)
            tokens.append(contentsOf: machoEditor.parseLinkerOptions(in: bytes))
            tokens.append(contentsOf: machoEditor.parseSwiftAutolinkEntries(in: bytes))
        }

        return directiveParser.parse(tokens)
    }

    /// Merges auto-detected dependencies and CLI overrides.
    func mergeAutolinkDirectives(auto: AutolinkDirectives, cli: RelinkOptions) -> AutolinkDirectives {
        let ignoredSet = Set(cli.ignoredAutolinkDependencies)

        return AutolinkDirectives(
            frameworkPaths: auto.frameworkPaths,
            libraryPaths: auto.libraryPaths,
            frameworks: auto.frameworks.subtracting(ignoredSet),
            weakFrameworks: auto.weakFrameworks.subtracting(ignoredSet),
            // `clang -dynamiclib` always supplies `-lSystem`; adding an auto-linked copy only creates a duplicate warning.
            libraries: auto.libraries.subtracting(ignoredSet).subtracting(["System"]),
            weakLibraries: auto.weakLibraries.subtracting(ignoredSet),
        )
    }

    /// Resolves all system-derived inputs needed to link one architecture slice.
    func makeDynamicSliceLinkContext(
        sdk: String,
        architecture: String,
        objectFiles: [URL],
        outputFile: URL,
        installName: String,
        autolinkDirectives: AutolinkDirectives,
        linkerArgs: [String],
    ) async throws -> DynamicSliceLinkContext {
        let sdkPath = try await resolveSDKPath(for: sdk)
        let targetTriples = try resolveTargetTriples(sdk: sdk, sdkPath: sdkPath, architecture: architecture)

        return DynamicSliceLinkContext(
            sdk: sdk,
            sdkPath: sdkPath,
            targetTriples: targetTriples,
            frameworkSearchRoots: frameworkSearchRoots(sdkPath: sdkPath, frameworkPaths: autolinkDirectives.frameworkPaths),
            architecture: architecture,
            objectFiles: objectFiles,
            outputFile: outputFile,
            installName: installName,
            autolinkDirectives: autolinkDirectives,
            linkerArgs: linkerArgs,
        )
    }

    /// Links one architecture slice through `clang -dynamiclib`.
    func buildDynamicSlice(context: DynamicSliceLinkContext) async throws {
        // Build the clang argument list for this architecture.
        var arguments = [
            // Produce a Mach-O dynamic library instead of an executable.
            "-dynamiclib",
            // Restrict this invocation to the current slice of a universal input.
            "-arch", context.architecture,
            // Resolve SDK frameworks and libraries against the selected Apple platform SDK.
            "-isysroot", context.sdkPath,
            // Write the requested LC_ID_DYLIB value into the output binary.
            "-install_name", context.installName,
            // Load Objective-C categories from the extracted object files.
            "-ObjC",
            // Link every extracted archive member rather than relying on archive member selection.
            "-all_load",
            // Remove unreachable code and data from the resulting dynamic library.
            "-Wl,-dead_strip",
            // Object files retain their `LC_LINKER_OPTION` records. Dependencies below are the filtered replacement.
            "-Wl,-ignore_auto_link",
        ]

        // Framework search paths discovered from LC_LINKER_OPTION / Swift autolink sections.
        context.autolinkDirectives.frameworkPaths.forEach { arguments.append(contentsOf: ["-F", $0]) }

        // Strong frameworks, filtered through SDK `.tbd` allowable-client metadata.
        frameworkFilter.allowedFrameworks(
            context.autolinkDirectives.frameworks,
            context: context,
        ).forEach { arguments.append(contentsOf: ["-framework", $0]) }

        // Weak frameworks use the same filtering, but keep their weak-linking semantics.
        frameworkFilter.allowedFrameworks(
            context.autolinkDirectives.weakFrameworks,
            context: context,
        ).forEach { arguments.append(contentsOf: ["-weak_framework", $0]) }

        // Library search paths from the input objects.
        context.autolinkDirectives.libraryPaths.forEach { arguments.append(contentsOf: ["-L", $0]) }

        // Swift runtime paths come from `swiftc -print-target-info` for the selected SDK target.
        let swiftRuntimeLibraryPaths = try await swiftRuntimeLibraryPaths(context: context)
        swiftRuntimeLibraryPaths.forEach { arguments.append(contentsOf: ["-L", $0]) }

        // Auto-linked libraries and explicit user-supplied linker arguments.
        context.autolinkDirectives.libraries.forEach { arguments.append("-l\($0)") }
        context.autolinkDirectives.weakLibraries.forEach { arguments.append("-weak-l\($0)") }
        arguments.append(contentsOf: context.linkerArgs)

        // Native object inputs and final output path.
        arguments.append(contentsOf: context.objectFiles.map(\.path))
        arguments.append(contentsOf: ["-o", context.outputFile.path])

        // Write arguments through a response file to avoid command-line length limits.
        let responseFileURL = environment.files.temporaryDirectory
            .appendingPathComponent("dylib_forge_\(UUID().uuidString)")
            .appendingPathExtension("rsp")
        try environment.files.write(clangResponseFileContents(arguments), to: responseFileURL)

        // Invoke clang through xcrun so the selected SDK controls tool resolution.
        let command = [
            "xcrun", "-sdk", context.sdk, "clang",
            "@\(responseFileURL.path)",
        ]

        _ = try await environment.shell.run(arguments: command)
    }
}

private extension ClangLinker {
    /// Returns Swift runtime library search paths for archives that carry Swift autolink libraries.
    func swiftRuntimeLibraryPaths(context: DynamicSliceLinkContext) async throws -> [String] {
        let linkedLibraries = context.autolinkDirectives.libraries.union(context.autolinkDirectives.weakLibraries)
        guard linkedLibraries.contains(where: { $0.hasPrefix("swift") }) else {
            return []
        }

        let result = try await environment.shell.run(
            "xcrun",
            "--sdk", context.sdk,
            "swiftc",
            "-target", context.targetTriples.swift,
            "-print-target-info",
        )
        let targetInfo = try JSONDecoder().decode(SwiftTargetInfo.self, from: Data(result.stdout.utf8))

        return targetInfo.paths.runtimeLibraryPaths
    }

    /// Returns the physical path to the selected SDK.
    func resolveSDKPath(for sdk: String) async throws -> String {
        let result = try await environment.shell.run("xcrun", "--sdk", sdk, "--show-sdk-path")
        let path = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !path.isEmpty else {
            throw DylibForgeError.message("Unable to determine SDK path for: \(sdk)")
        }

        return path
    }

    /// Builds Swift and TAPI target triples from the selected SDK's own metadata.
    func resolveTargetTriples(sdk: String, sdkPath: String, architecture: String) throws -> SDKTargetTriples {
        let settingsURL = URL(fileURLWithPath: sdkPath, isDirectory: true).appendingPathComponent("SDKSettings.plist")
        let settingsData = try Data(contentsOf: settingsURL)
        let settings = try PropertyListDecoder().decode(SDKSettings.self, from: settingsData)

        guard let target = settings.supportedTargets[sdk]
            ?? settings.supportedTargets.first(where: { sdk.hasPrefix($0.key) })?.value
        else {
            throw DylibForgeError.message("SDK '\(sdk)' has no supported target definition: \(sdkPath)")
        }

        let environmentSuffix = target.llvmTargetTripleEnvironment.map { "-\($0)" } ?? ""
        let sysWithVersion = "\(target.llvmTargetTripleSys)\(target.defaultDeploymentTarget)"
        let swiftTargetTriple = "\(architecture)-\(target.llvmTargetTripleVendor)-\(sysWithVersion)\(environmentSuffix)"
        let tbdSystem = target.llvmTargetTripleSys == "macosx" ? "macos" : target.llvmTargetTripleSys
        let tbdTargetTriple = "\(architecture)-\(tbdSystem)\(environmentSuffix)"

        return SDKTargetTriples(swift: swiftTargetTriple, tbd: tbdTargetTriple)
    }

    /// Returns framework search roots used for inspecting SDK `.tbd` stubs.
    func frameworkSearchRoots(sdkPath: String, frameworkPaths: Set<String>) -> [URL] {
        let explicitFrameworkRoots = frameworkPaths.map { URL(fileURLWithPath: $0, isDirectory: true) }
        let sdkURL = URL(fileURLWithPath: sdkPath, isDirectory: true)

        return explicitFrameworkRoots + [sdkURL]
    }

    /// Serializes clang argv entries for a response file, preserving each original argument as one escaped token.
    func clangResponseFileContents(_ arguments: [String]) -> String {
        arguments
            .map { argument in
                let escaped = argument
                    .replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "\"", with: "\\\"")
                return "\"\(escaped)\""
            }
            .joined(separator: "\n")
    }
}
