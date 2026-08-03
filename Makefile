# Developer commands.
.PHONY: format format-check release

NATIVE_SOURCE_FILES := $(shell find Sources AcceptanceTests -type f \( -name '*.c' -o -name '*.cc' -o -name '*.cpp' -o -name '*.cxx' -o -name '*.h' -o -name '*.hpp' -o -name '*.m' -o -name '*.mm' \) -not -path '*/.build/*' -not -path '*/.xcodeproj/*')

# Keep release logs focused on tool output rather than echoed shell commands.
.SILENT: format format-check release

# Formats every Swift, C, C++, and Objective-C source, including acceptance fixtures and the client project.
format:
	swift run swiftformat Package.swift Sources AcceptanceTests --swiftversion 6.2
	xcrun clang-format -i $(NATIVE_SOURCE_FILES)

# Checks every Swift, C, C++, and Objective-C source without modifying it; suitable for CI.
format-check:
	swift run swiftformat Package.swift Sources AcceptanceTests --swiftversion 6.2 --lint
	xcrun clang-format --dry-run --Werror $(NATIVE_SOURCE_FILES)

# Builds a universal macOS `dylib-forge` executable and packages it as `dylib-forge.zip`.
release:
	swift build -c release --arch x86_64 --product dylib-forge
	swift build -c release --arch arm64 --product dylib-forge
	lipo -create .build/x86_64-apple-macosx/release/dylib-forge .build/arm64-apple-macosx/release/dylib-forge -output ./dylib-forge
	strip -rSTx ./dylib-forge
	lipo -info ./dylib-forge
	# Rebuild the archive from the current binary; `-m` removes that temporary binary afterward.
	rm -f ./dylib-forge.zip
	zip -j -m ./dylib-forge.zip ./dylib-forge
