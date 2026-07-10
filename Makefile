format:
	swift package plugin --allow-writing-to-package-directory swiftformat

release:
	swift build -c release --arch x86_64 --product dylib-forge
	swift build -c release --arch arm64 --product dylib-forge
	lipo -create .build/x86_64-apple-macosx/release/dylib-forge .build/arm64-apple-macosx/release/dylib-forge -output ./dylib-forge
	strip -x ./dylib-forge
	lipo -info ./dylib-forge
	rm -f ./dylib-forge.zip
	zip -j ./dylib-forge.zip ./dylib-forge
	rm -f ./dylib-forge
