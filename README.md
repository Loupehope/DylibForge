<img src="./media/logo.svg" alt="Project logo" width="300">

# DylibForge

DylibForge converts static Apple `ar` archives into dynamic Mach-O libraries. It has two command-line tools built on the same relinking engine:

- [dylib-forge-xc](#convert-an-xcframework) converts a complete XCFramework.
- [dylib-forge](#convert-one-archive-or-framework-binary) converts one archive or one static framework binary.

Download the latest binaries from [GitHub Releases](https://github.com/Loupehope/DylibForge/releases/latest).

## Convert an XCFramework

Use `dylib-forge-xc` to convert a complete XCFramework. The output path may be the same as the input path.

```bash
dylib-forge-xc ./GoogleMaps.xcframework \
  --output ./GoogleMapsDynamic.xcframework
```

| Argument | Required | Meaning |
| --- | --- | --- |
| `<input>` | Yes | Source `.xcframework` path. |
| `--output <path>` | Yes | Converted `.xcframework` path. |
| `--linker-arg-sdk <sdk-or-arg>` | No | SDK name or `any` followed by raw linker arguments. |
| `--ignore-autolink-sdk <sdk-or-name>` | No | SDK name or `any` followed by autolink dependency names to ignore. |
| `--exclude-object-sdk <sdk-or-pattern>` | No | SDK name or `any` followed by archive object name patterns to exclude. |
| `--xcframework-dependency <path>` | No | Dependency `.xcframework` path. Its matching platform, variant, and architecture slice is linked. |

The command handles every supported static artifact in the XCFramework:

- Converts a `.a` archive into a `.dylib` and rebuilds a static framework executable in place.
- Derives the SDK and install name from the XCFramework metadata and updates the root `Info.plist`.
- Preserves all other package data, including headers, modules, debug symbols, and dynamic artifacts.
- Removes code signatures and does not sign the result.

> Mac Catalyst artifacts are not supported. They are omitted from the output XCFramework and its root `Info.plist`. The command logs a warning.

### SDK-Specific Linker Arguments

Use SDK-specific controls when linker arguments, ignored autolink dependencies, or excluded archive objects differ between SDKs:

- Start each group with an SDK name or `any`.
- DylibForge applies every following value to slices built with that SDK until it encounters another SDK name.
- Values in an `any` group apply to every slice, and values from a specific SDK group are added only to that SDK's slices.

```bash
dylib-forge-xc ./Library.xcframework --output ./LibraryDynamic.xcframework \
  --linker-arg-sdk any \
  --linker-arg-sdk -lc++ \
  --linker-arg-sdk iphoneos \
  --linker-arg-sdk -framework \
  --linker-arg-sdk CoreMedia \
  --linker-arg-sdk iphonesimulator \
  --linker-arg-sdk -Wl,-weak_framework,ARKit
```

This links `-lc++` for every slice, `CoreMedia` only for iOS-device slices, and weakly links `ARKit` only for Simulator slices.

### Link Another XCFramework

Use `--xcframework-dependency` when the dependency is itself an XCFramework. DylibForge finds the slice with the same platform, variant, and architecture as the library currently being rebuilt, then adds its framework search path and framework name to the linker invocation.

```bash
dylib-forge-xc ./Library.xcframework \
  --output ./LibraryDynamic.xcframework \
  --xcframework-dependency ./VendorSDK.xcframework
```

The same dependency can also be specified explicitly with `--linker-arg-sdk`:

```bash
dylib-forge-xc ./Library.xcframework --output ./LibraryDynamic.xcframework \
  --linker-arg-sdk iphoneos \
  --linker-arg-sdk -F \
  --linker-arg-sdk ./VendorSDK.xcframework/ios-arm64 \
  --linker-arg-sdk -framework \
  --linker-arg-sdk VendorSDK \
  --linker-arg-sdk iphonesimulator \
  --linker-arg-sdk -F \
  --linker-arg-sdk ./VendorSDK.xcframework/ios-arm64_x86_64-simulator \
  --linker-arg-sdk -framework \
  --linker-arg-sdk VendorSDK
```

## Convert One Archive or Framework Binary

Use `dylib-forge` to convert one standalone archive or framework executable. The output path may be the same as the input path.

```bash
dylib-forge ./AbstractMaps.framework/AbstractMaps \
  --output ./AbstractMaps.framework/AbstractMaps \
  --sdk iphoneos \
  --install-name @rpath/AbstractMaps.framework/AbstractMaps \
  --linker-arg -framework --linker-arg UIKit \
  --ignore-autolink PrivateVendorShim \
  --exclude-object LegacySimulatorOnly
```

| Argument | Required | Meaning |
| --- | --- | --- |
| `<input>` | Yes | Path to a static `.a` archive or to the executable inside a static framework. |
| `--output <path>` | Yes | Where to write the dynamic binary. |
| `--sdk <sdk>` | Yes | SDK used for linking, such as `iphoneos`, `iphonesimulator`, `watchos`, or `watchsimulator`. |
| `--install-name <name>` | Yes | Value written to `LC_ID_DYLIB`, for example `@rpath/Foo.framework/Foo`. |
| `--linker-arg <arg>` | No | Additional raw argument passed to clang while linking. |
| `--ignore-autolink <name>` | No | Auto-detected autolink dependency name to ignore. |
| `--exclude-object <pattern>` | No | Object file name substring to skip while unpacking the archive. |

The command:

- Unpacks the `ar` archive into Mach-O object files and patches Objective-C symbol visibility.
- Drops byte-identical object files and localizes overlapping native symbol definitions.
- Links the remaining objects into a dynamic binary at `--output` using the supplied SDK and install name.

> When the input is a framework executable, this command only converts that executable. It does not copy the framework directory, update a parent XCFramework manifest, remove signatures, or sign the result.

## Resolve Dependencies

You can either defer undefined symbols to the app that loads the dylib, or link each dependency explicitly.

### Resolve Undefined Symbols at Runtime

For a quick attempt at unresolved symbols, pass `-Wl,-undefined,dynamic_lookup` through a `--linker-arg-sdk any` group:

```bash
dylib-forge-xc ./GoogleMaps.xcframework \
  --output ./GoogleMapsDynamic.xcframework \
  --linker-arg-sdk any \
  --linker-arg-sdk -Wl,-undefined,dynamic_lookup
```

This asks the final app to resolve undefined symbols at load time. Apple deprecates `dynamic_lookup`, so explicit linking is preferable when practical.

### Link Dependencies Explicitly

Instead of `-Wl,-undefined,dynamic_lookup`, pass the frameworks and libraries that the dynamic binary should link.

```bash
dylib-forge-xc ./GoogleMaps.xcframework \
  --output ./GoogleMapsDynamic.xcframework \
  --linker-arg-sdk any \
  --linker-arg-sdk -framework \
  --linker-arg-sdk Foundation \
  --linker-arg-sdk -lc++ \
  --linker-arg-sdk -F"Framework/Search/Path" \
  --linker-arg-sdk -Wl,-U,_some_undefined_symbol \
  --ignore-autolink-sdk any \
  --ignore-autolink-sdk PrivateVendorShim \
  --exclude-object-sdk any \
  --exclude-object-sdk LegacySimulatorOnly
```

## Architecture Support

Both tools handle input archives and framework binaries that contain several architecture slices. Before relinking a static slice, DylibForge asks the currently selected Xcode (`xcode-select`) whether its SDK and toolchain support that target. If they do not, the tool logs a warning and continues with the remaining supported architectures.

If an architecture is skipped during `dylib-forge-xc`, the output root `Info.plist` is updated. Its `AvailableLibraries` entry receives the actual `SupportedArchitectures`, and a converted archive receives its new `.dylib` `LibraryPath`. The library identifier and directory stay the same, so every manifest path continues to resolve.

## Inspiration

The idea for this project came from these materials:

- English article: [Convert Static Framework to Dynamic](https://pewpewthespells.com/blog/convert_static_to_dynamic.html)
- Russian talk: [How Far Would You Go for Working Breakpoints, Vladimir Ozerov](https://developers.sber.ru/kak-v-sbere/events/ios_october)

## Disclaimer

DylibForge is licensed under the MIT License and was originally developed for research purposes. It is provided as-is.

You are responsible for ensuring that you have the right to process, redistribute, ship, or otherwise use any third-party binaries with this tool, including compliance with vendor licenses, Apple platform rules, and applicable legal requirements.

This README is not legal advice.
