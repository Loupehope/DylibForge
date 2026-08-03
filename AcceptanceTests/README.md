# DylibForge acceptance tests

This directory contains reproducible end-to-end fixtures for `dylib-forge xc`. The root SwiftPM executable `dylib-forge-tests acceptance` generates the Xcode projects with XcodeGen, builds each fixture as a static XCFramework, converts it with `dylib-forge xc`, and validates the converted frameworks in a client.

Every fixture has five slices:

- macOS;
- iOS device and iOS Simulator;
- watchOS device and watchOS Simulator.

The generated macOS client executes the shared Swift validation in a child process. The same validation runs through Swift Testing on iOS Simulator and watchOS Simulator. Every fixture exposes a validator instance with `validate()` and returns the common expected value `42` as a Swift `Int`.

The suite stores and checks the logs from the macOS client build, iOS Simulator test build, and watchOS Simulator test build. A linker warning or error about duplicate symbols fails the suite. Generated projects, archives, static and relinked XCFrameworks, derived data, and these logs are stored only in `AcceptanceTests/.build`.

## Run

Install [mise](https://mise.jdx.dev/) and select an Xcode installation that includes the macOS, iOS, and watchOS SDKs. The root [`mise.toml`](../mise.toml) pins XcodeGen.

Run from the repository root:

```bash
mise install
swift run dylib-forge-tests acceptance --xcode-path /Applications/Xcode.app
```

Omit `--xcode-path` to use the Xcode selected by `xcode-select`. Set `XCODEGEN=/path/to/xcodegen` only when developing with a local XcodeGen executable instead of the pinned mise tool.

All human-readable `xcodebuild` invocations run through the pinned `xcbeautify`. The executor enables `pipefail`, `NSUnbufferedIO=YES`, and redirects stderr to stdout, so concurrent Xcode output is formatted without hiding a failed build. The `xcodebuild -showsdks -json` SDK-discovery command intentionally remains raw because xcbeautify does not preserve its JSON output.

Fixture slices and independent relink operations run concurrently. `concurrentMap` limits the number of active processes to `ProcessInfo.processInfo.activeProcessorCount`; fixtures that depend on another relinked XCFramework wait for that dependency.

## Fixtures

- `StaticFrameworkWithPrivateObjC` contains an Objective-C class with hidden visibility. The client constructs the class directly, requiring the relinker to export its metadata.
- `StaticFrameworkWithCxxDependency` calls a function defined in its nested `CxxStaticDependency` static-library target. A post-build `libtool` step merges that dependency into the fixture framework archive, ensuring the relinker processes objects from both archives.
- `StaticFrameworkWithDuplicateObjects` verifies byte-identical native object deduplication. The target compiles `RepeatedObject.cpp` once, then its Xcode build phase uses `libtool` to append that exact compiled `RepeatedObject.o` to the static framework archive a second time. The archive therefore has two members with identical payloads, rather than merely two similar C++ source files.

  `RepeatedObject.o` defines a load-time C++ registration that increments a shared counter and a function that returns `41`. The client validator returns the function value plus that counter. `NativeObjectDuplicateTracker` must discard the second archive member: one registration gives the common expected result `42`. If object deduplication is removed, both registrations run after relinking and the validator returns `43`; the macOS client and both Swift Testing targets then fail their shared validation.

- `StaticFrameworkWithDuplicateSymbols` verifies localization of repeated external native definitions. It contains two non-identical C++ objects: each defines `repeated_measurement()`, while one additionally defines `repeated_measurement_a()` and the other `repeated_measurement_b()`. The client must retain both objects to call the unique functions, and their values `1 + 20 + 21` produce the common expected result `42`.

  Because the object payloads differ, object deduplication deliberately cannot remove either one. Instead, `makeExternalNativeDefinitionsLocal` changes the duplicated `repeated_measurement()` definition in the later object from external to local before `clang` links the dynamic slice. If that step is removed, relinking fails with a duplicate-symbol diagnostic for `dylib_forge_acceptance::repeated_measurement()`.
- `StaticFrameworkWithExcludedObject` contains `ReleaseOnlyGhost.o`, which calls a deliberately missing C symbol. The validator discovers the ghost entry point through `dlsym`: when the fixture description supplies `--exclude-object-sdk ReleaseOnlyGhost`, the entry point is absent and validation returns `42`. If the object is included with `-undefined dynamic_lookup`, validation calls it and dyld fails to resolve the missing symbol at runtime.
- `StaticFrameworkWithSwift` contains only a public Swift validation API returning `Int`.
- `StaticLibraryWithSwift` is a Swift `library.static` target rather than a framework. Its Xcode build phase installs `StaticLibraryWithSwift.swiftmodule` beside the archive's `.a`, so `xcodebuild -create-xcframework` preserves import metadata before relinking the `.a` into a `.dylib`. A Swift module directory—not a Clang `module.modulemap`—describes the Swift API.
- `StaticFrameworkWithSwiftXCFrameworkDependency` is one scenario with two frameworks: `StaticFrameworkWithSwiftDependency` and `StaticFrameworkWithSwiftDependentFramework`. The latter imports the former; when relinked, it receives the converted dependency through `--xcframework-dependency`.
- `StaticFrameworkWithObjC` contains only an Objective-C implementation with a public C entry point.
- `StaticFrameworkWithObjCAndSwift` exercises a Swift-to-Objective-C call. Swift invokes an Objective-C C-compatible entry point, which calls an Objective-C class before returning the validation value.

## Add a fixture

1. Add the fixture source under `FixturesProject/Fixtures/<FixtureName>/Sources` and any public headers under `include`.
2. Add five XcodeGen targets—one for every `Platform` case—to `FixturesProject/project.yml`. Keep extra implementation targets inside the same fixture directory, as the C++ and Swift dependency scenarios do.
3. Add the fixture to `Sources/DylibForgeAcceptanceTests/Common/Fixtures.swift`. Put fixture-specific `dylib-forge xc` options in `relinkingArguments` and converted-XCFramework dependencies in `xcframeworkDependencies`. For a static library, declare its `archiveProduct` and ensure its Swift module is installed into the archive.
4. Add the relinked XCFramework to the macOS client and both simulator Swift Testing targets in `ClientProject/project.yml`.
5. Import the fixture module and add its validator construction and `validate()` call to `ClientProject/Validation/Sources/FixtureValidation.swift`. The common validation layer must produce an `Int`.

Only inputs and automation are tracked in Git: fixture source, XcodeGen specifications, root SwiftPM code, and documentation. Delete `AcceptanceTests/.build` to force a clean acceptance run.
