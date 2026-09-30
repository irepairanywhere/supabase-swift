# Mouthful for iPhone – developer shortcuts. The real work happens in ../Makefile.
.PHONY: xcodeproj open clean

## Generate MouthfulMobile.xcodeproj (downloads XcodeGen on first use if Homebrew's is absent)
xcodeproj:
	$(MAKE) -C .. iphone-project

## Generate and open in Xcode
open:
	$(MAKE) -C .. iphone

clean:
	rm -rf MouthfulMobile.xcodeproj build DerivedData
