# Dictum for iPhone – developer shortcuts. Run from this directory.
.PHONY: xcodeproj open clean

## Generate DictumMobile.xcodeproj (requires: brew install xcodegen)
xcodeproj:
	xcodegen generate

## Generate and open in Xcode
open: xcodeproj
	open DictumMobile.xcodeproj

clean:
	rm -rf DictumMobile.xcodeproj build DerivedData
