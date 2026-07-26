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
| `<input>` | Yes | Path to the source `.xcframework`. |
| `--output <path>` | Yes | Path for the converted `.xcframework`. |

The command handles every supported static artifact in the XCFramework:

- Converts a `.a` archive into a `.dylib` and rebuilds a static framework executable in place.
- Derives the SDK and install name from the XCFramework metadata and updates the root `Info.plist`.
- Preserves all other package data, including headers, modules, debug symbols, and dynamic artifacts.
- Removes code signatures and does not sign the result.

> Mac Catalyst artifacts are not supported. They are omitted from the output XCFramework and its root `Info.plist`. The command logs a warning.

## Convert One Archive or Framework Binary

Use `dylib-forge` to convert one standalone archive or framework executable. The output path may be the same as the input path.

```bash
dylib-forge ./AbstractMaps.framework/AbstractMaps \
  --output ./AbstractMaps.framework/AbstractMaps \
  --sdk iphoneos \
  --install-name @rpath/AbstractMaps.framework/AbstractMaps
```

| Argument | Required | Meaning |
| --- | --- | --- |
| `<input>` | Yes | Path to a static `.a` archive or to the executable inside a static framework. |
| `--output <path>` | Yes | Where to write the dynamic binary. |
| `--sdk <sdk>` | Yes | SDK used for linking, such as `iphoneos`, `iphonesimulator`, `watchos`, or `watchsimulator`. |
| `--install-name <name>` | Yes | Value written to `LC_ID_DYLIB`, for example `@rpath/Foo.framework/Foo`. |

The command:

- Unpacks the `ar` archive into Mach-O object files and patches Objective-C symbol visibility.
- Drops byte-identical object files and localizes overlapping native symbol definitions.
- Links the remaining objects into a dynamic binary at `--output` using the supplied SDK and install name.

> When the input is a framework executable, this command only converts that executable. It does not copy the framework directory, update a parent XCFramework manifest, remove signatures, or sign the result.

## Optional Relinking Controls

Both commands accept the controls below. Use them when the archive's autolink metadata is incomplete, incorrect, or references dependencies unavailable in the selected SDK.

```text
--linker-arg <arg>            Additional raw argument passed to clang while linking.
--ignore-autolink <name>      Auto-detected autolink dependency name to ignore.
--exclude-object <pattern>    Object file name substring to skip while unpacking the archive.
```

`--linker-arg` accepts values beginning with `-`:

```bash
--linker-arg -framework --linker-arg UIKit
--linker-arg -lc++
--linker-arg "-Wl,-rpath,@loader_path/Frameworks"
```

### Resolve Dependencies

You can either defer undefined symbols to the app that loads the dylib, or link each dependency explicitly.

#### Resolve Undefined Symbols at Runtime

For a quick attempt at unresolved symbols, pass `--linker-arg "-Wl,-undefined,dynamic_lookup"`:

```bash
dylib-forge-xc ./GoogleMaps.xcframework \
  --output ./GoogleMapsDynamic.xcframework \
  --linker-arg "-Wl,-undefined,dynamic_lookup"
```

This asks the final app to resolve undefined symbols at load time. Apple deprecates `dynamic_lookup`, so explicit linking is preferable when practical.

#### Link Dependencies Explicitly

Instead of `-Wl,-undefined,dynamic_lookup`, pass the frameworks and libraries that the dynamic binary should link.

```bash
dylib-forge-xc ./GoogleMaps.xcframework \
  --output ./GoogleMapsDynamic.xcframework \
  --linker-arg -framework --linker-arg Foundation \
  --linker-arg -lc++ \
  --linker-arg -F"Framework/Search/Path" \
  --linker-arg -Wl,-U,_some_undefined_symbol \
  --ignore-autolink PrivateVendorShim \
  --exclude-object LegacySimulatorOnly
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
