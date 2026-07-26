# Developer commands.
.PHONY: format release release-dylib-forge release-dylib-forge-xc

# Keep release logs focused on tool output rather than echoed shell commands.
.SILENT: release-dylib-forge release-dylib-forge-xc

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

# Formats all Swift sources through the package plugin.
format:
	swift package plugin --allow-writing-to-package-directory swiftformat

# Packages every public command-line executable.
release: release-dylib-forge release-dylib-forge-xc

# Packages the static-archive-to-dylib converter as `dylib-forge.zip`.
release-dylib-forge:
	$(call release_binary,dylib-forge)

# Packages the XCFramework converter as `dylib-forge-xc.zip`.
release-dylib-forge-xc:
	$(call release_binary,dylib-forge-xc)
