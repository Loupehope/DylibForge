<img src="./media/logo.svg" alt="Project logo" width="300">

# DylibForge

DylibForge is a macOS command-line tool for relinking a static Apple `ar` archive into a dynamic Mach-O binary.

It extracts Mach-O objects, preserves autolink directives, patches Objective-C symbol visibility, skips byte-identical object members, localizes selected duplicate native definitions, and then drives `clang -dynamiclib`.

## Basic Usage

```bash
dylib-forge ./AbstractMaps.framework/AbstractMaps \
  --output ./AbstractMaps.framework/AbstractMaps \
  --sdk iphoneos \
  --install-name @rpath/AbstractMaps.framework/AbstractMaps
```

## Options

```text
<input>                       Path to the input static ar archive or static framework binary.
--output <path>               Required output path for the generated dynamic binary.
--sdk <sdk>                   Apple SDK used for linking, for example iphoneos, iphonesimulator, watchos, or watchsimulator.
--install-name <name>         Required install name written into LC_ID_DYLIB.
--linker-arg <arg>            Additional raw argument passed to clang while linking.
--ignore-autolink <name>      Auto-detected autolink dependency name to ignore.
--exclude-object <pattern>    Object file name substring to skip while unpacking the archive.
```

`--linker-arg` uses unconditional single-value parsing, so arguments that begin with `-` are accepted as values:

```bash
--linker-arg -framework --linker-arg UIKit
--linker-arg -lc++
--linker-arg "-Wl,-rpath,@loader_path/Frameworks"
```

## Example

### Easy way

Most unresolved-symbol problems can be sidestepped by asking the final app to resolve them at load/runtime:

```bash
dylib-forge ./AbstractMaps.framework/AbstractMaps \
  --output ./AbstractMaps.framework/AbstractMaps \
  --sdk iphoneos \
  --install-name @rpath/AbstractMaps.framework/AbstractMaps \
  --linker-arg "-Wl,-undefined,dynamic_lookup"
```

For many vendor archives this is enough: `-Wl,-undefined,dynamic_lookup` leaves symbol resolution to the app that loads the dynamic library, so you do not need to model every dependency during relinking.

Keep in mind that `dynamic_lookup` is deprecated by Apple and may disappear in the future.

### Jedi way

Instead of `-Wl,-undefined,dynamic_lookup`, you can pass the exact frameworks and libraries that should be linked into the generated dynamic binary.

```bash
dylib-forge ./AbstractMaps.framework/AbstractMaps \
  --output ./AbstractMaps.framework/AbstractMaps \
  --sdk iphoneos \
  --install-name @rpath/AbstractMaps.framework/AbstractMaps \
  --linker-arg -framework --linker-arg Foundation \
  --linker-arg -lc++ \
  --linker-arg -F"Framework/Search/Path" \
  --linker-arg -Wl,-U,_some_undefined_symbol \
  --ignore-autolink PrivateVendorShim \
  --exclude-object LegacySimulatorOnly
```

This path is more explicit and easier to audit, but different vendors build their libraries in different ways. You may still need to leave a specific symbol undefined with `-Wl,-U,_some_undefined_symbol`, add framework search paths with `-F`, ignore a bad autolink entry with `--ignore-autolink`, or exclude an object that does not belong in the final binary with `--exclude-object`.

## Tips

- Set a minimum OS version with `--linker-arg -m<os>-version-min=<version>`, for example `--linker-arg -mios-simulator-version-min=18.0`.

## Inspiration

The idea for this project came from these materials:

- English article: [Convert Static Framework to Dynamic](https://pewpewthespells.com/blog/convert_static_to_dynamic.html)
- Russian talk: [How Far Would You Go for Working Breakpoints, Vladimir Ozerov](https://developers.sber.ru/kak-v-sbere/events/ios_october)

## Disclaimer

DylibForge is licensed under the MIT License and was originally developed for research purposes. It is provided as-is.

You are responsible for ensuring that you have the right to process, redistribute, ship, or otherwise use any third-party binaries with this tool, including compliance with vendor licenses, Apple platform rules, and applicable legal requirements.

This README is not legal advice.
