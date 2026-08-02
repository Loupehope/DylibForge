# Developer commands.
.PHONY: format format-check release release-dylib-forge release-dylib-forge-xc

NATIVE_SOURCE_FILES := $(shell find Sources AcceptanceTests -type f \( -name '*.c' -o -name '*.cc' -o -name '*.cpp' -o -name '*.cxx' -o -name '*.h' -o -name '*.hpp' -o -name '*.m' -o -name '*.mm' \) -not -path '*/.build/*' -not -path '*/.xcodeproj/*')

# Keep release logs focused on tool output rather than echoed shell commands.
.SILENT: format format-check release release-dylib-forge release-dylib-forge-xc

# Builds a universal macOS executable and packages it as `<product>.zip`.
#
# Usage: $(call release_binary,<product>)
define release_binary
	swift build -c release --arch x86_64 --product $(1)
	swift build -c release --arch arm64 --product $(1)
	lipo -create .build/x86_64-apple-macosx/release/$(1) .build/arm64-apple-macosx/release/$(1) -output ./$(1)
	strip -rSTx ./$(1)
	lipo -info ./$(1)
	# Rebuild the archive from the current binary; `-m` removes that temporary binary afterward.
	rm -f ./$(1).zip
	zip -j -m ./$(1).zip ./$(1)
endef

# Formats every Swift, C, C++, and Objective-C source, including acceptance fixtures and the client project.
format:
	swift run swiftformat Package.swift Sources AcceptanceTests --swiftversion 6.2
	xcrun clang-format -i $(NATIVE_SOURCE_FILES)

# Checks every Swift, C, C++, and Objective-C source without modifying it; suitable for CI.
format-check:
	swift run swiftformat Package.swift Sources AcceptanceTests --swiftversion 6.2 --lint
	xcrun clang-format --dry-run --Werror $(NATIVE_SOURCE_FILES)

# Packages every public command-line executable.
release: release-dylib-forge release-dylib-forge-xc

# Packages the static-archive-to-dylib converter as `dylib-forge.zip`.
release-dylib-forge:
	$(call release_binary,dylib-forge)

# Packages the XCFramework converter as `dylib-forge-xc.zip`.
release-dylib-forge-xc:
	$(call release_binary,dylib-forge-xc)
