# DylibForge acceptance tests

`dylib-forge-tests acceptance` generates fixture and client Xcode projects, archives every fixture as a static XCFramework, converts it with `dylib-forge xc`, then validates the result with Swift Testing on macOS, iOS Simulator, and watchOS Simulator.

Each fixture contains macOS, iOS/device, iOS Simulator, watchOS/device, and watchOS Simulator slices. Generated projects, archives, XCFrameworks, derived data, and logs live in `AcceptanceTests/.build` only. Duplicate-symbol diagnostics in any client test log fail the suite.

## Run

Install the pinned tools and select an Xcode with the macOS, iOS, and watchOS SDKs:

```bash
mise install
swift run dylib-forge-tests acceptance --xcode-path /Applications/Xcode.app
```

Omit `--xcode-path` to use `xcode-select`. The pinned `xcbeautify` formats human-readable `xcodebuild` output. The JSON SDK-discovery query remains unformatted. Independent fixture stages, relinking, and client test schemes run in parallel.

## Deployment targets

`deployment-targets.json` is the single source of truth for the minimum macOS, iOS, and watchOS versions. The acceptance runner passes these values to both XcodeGen projects and to `dylib-forge xc`, so fixture slices, relinked dylibs, and the validation client remain compatible. A simulator runtime must be no older than its configured deployment target and no newer than the selected Xcode SDK.

## Fixtures

- `StaticFrameworkWithPrivateObjC` — private Objective-C metadata export.
- `StaticFrameworkWithCxxDependency` — merged C++ static-library dependency.
- `StaticFrameworkWithDuplicateObjects` — deduplicates byte-identical native objects. The runtime validator confirms that only one copy ran its load-time registration.
- `StaticFrameworkWithDuplicateSymbols` — localizes repeated native definitions while retaining each object's distinct required symbol. Without localization, relinking reports duplicate symbols.
- `StaticFrameworkWithExcludedObject` — excludes an object with a missing runtime symbol. Including the object makes runtime resolution fail.
- `StaticFrameworkWithSwift` and `StaticLibraryWithSwift` — Swift framework and static library conversion.
- `StaticFrameworkWithSwiftXCFrameworkDependency` — one converted Swift XCFramework depending on another.
- `StaticFrameworkWithObjC` and `StaticFrameworkWithObjCAndSwift` — Objective-C and mixed-language calls.

All fixture validators return the shared expected `Int` value, `42`.

## Add a fixture

1. Add sources under `FixturesProject/Fixtures/<FixtureName>`.
2. Add five XcodeGen targets in `FixturesProject/project.yml` and the `Fixture` case in Swift.
3. Add the relinked XCFramework to each client test target and invoke its validator from `ClientProject/Validation`.

Delete `AcceptanceTests/.build` for a clean run.
