# DylibForge acceptance tests

This directory contains reproducible end-to-end fixtures for `dylib-forge-xc`. The root SwiftPM executable `dylib-forge-tests acceptance` generates the Xcode projects with XcodeGen, builds each fixture as a static XCFramework, converts it with `dylib-forge-xc`, and validates the converted frameworks in a client.

Every fixture has five slices:

- macOS;
- iOS device and iOS Simulator;
- watchOS device and watchOS Simulator.

The generated macOS app executes the shared Swift validation at runtime. The same validation is executed in XCTest bundles on iOS Simulator and watchOS Simulator. Every fixture exposes `validate()` and must return the common expected value `42` as a Swift `Int`; C and Objective-C APIs are converted from their imported `Int32` result at the client boundary.

The suite stores and checks the logs from the macOS client build, iOS Simulator test build, and watchOS Simulator test build. A linker warning or error about duplicate symbols fails the suite. Generated projects, archives, static and relinked XCFrameworks, derived data, and these logs are stored only in `AcceptanceTests/.build`.

## Run

Install [mise](https://mise.jdx.dev/) and select an Xcode installation that includes the macOS, iOS, and watchOS SDKs. The root [`mise.toml`](../mise.toml) pins XcodeGen.

Run from the repository root:

```bash
mise install
swift run dylib-forge-tests acceptance --xcode-path /Applications/Xcode.app
```

Omit `--xcode-path` to use the Xcode selected by `xcode-select`. Set `XCODEGEN=/path/to/xcodegen` only when developing with a local XcodeGen executable instead of the pinned mise tool.

Fixture slices and independent relink operations run concurrently. `concurrentMap` limits the number of active processes to `ProcessInfo.processInfo.activeProcessorCount`; fixtures that depend on another relinked XCFramework wait for that dependency.

## Fixtures

- `StaticFrameworkWithPrivateObjC` contains an Objective-C class with hidden visibility and validates its public C entry point.
- `StaticFrameworkWithCxxDependency` calls a function defined in its nested `CxxStaticDependency` static-library target. A post-build `libtool` step merges that dependency into the fixture framework archive, ensuring the relinker processes objects from both archives.
- `StaticFrameworkWithDuplicateSymbols` contains byte-identical native definitions and exercises DylibForge's duplicate-object handling.
- `StaticFrameworkWithExcludedObject` contains an intentionally excluded object file. Its fixture description supplies the required `--exclude-object-sdk` arguments to the relinker.
- `StaticFrameworkWithSwift` contains only a public Swift `validate() -> Int` API.
- `StaticFrameworkWithSwiftXCFrameworkDependency` is one scenario with two frameworks: `StaticFrameworkWithSwiftDependency` and `StaticFrameworkWithSwiftDependentFramework`. The latter imports the former; when relinked, it receives the converted dependency through `--xcframework-dependency`.
- `StaticFrameworkWithObjC` contains only an Objective-C implementation with a public C entry point.
- `StaticFrameworkWithObjCAndSwift` exercises a Swift-to-Objective-C call. Swift invokes an Objective-C C-compatible entry point, which calls an Objective-C class before returning the validation value.

## Add a fixture

1. Add the fixture source under `FixturesProject/Fixtures/<FixtureName>/Sources` and any public headers under `include`.
2. Add five XcodeGen targets—one for every `Platform` case—to `FixturesProject/project.yml`. Keep extra implementation targets inside the same fixture directory, as the C++ and Swift dependency scenarios do.
3. Add the fixture to `Sources/DylibForgeAcceptanceTests/Common/Fixture.swift`. Put fixture-specific `dylib-forge-xc` options in `relinkingArguments` and converted-XCFramework dependencies in `xcframeworkDependencies`.
4. Add the relinked XCFramework to the macOS client and both simulator XCTest targets in `ClientProject/project.yml`.
5. Import the fixture module and add its `validate()` call to `ClientProject/Validation/Sources/FixtureValidation.swift`. The common validation layer must produce an `Int`.

Only inputs and automation are tracked in Git: fixture source, XcodeGen specifications, root SwiftPM code, and documentation. Delete `AcceptanceTests/.build` to force a clean acceptance run.
