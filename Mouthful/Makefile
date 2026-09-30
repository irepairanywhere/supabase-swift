# Mouthful – developer shortcuts. Run from this directory.
APP = build/Mouthful.app

# XcodeGen turns project.yml into an .xcodeproj. A Homebrew install is used when present;
# otherwise the official release is downloaded into .tools/ (no Homebrew, no sudo).
XCODEGEN := $(shell command -v xcodegen 2>/dev/null)
ifeq ($(XCODEGEN),)
XCODEGEN := .tools/xcodegen/bin/xcodegen
endif
XCODEGEN_ZIP = https://github.com/yonaskolb/XcodeGen/releases/latest/download/xcodegen.zip

.PHONY: app run zip install iphone iphone-project xcodeproj test-core clean

## Build a release .app bundle into build/
app:
	./scripts/build-app.sh

## Build and launch
run: app
	open $(APP)

## Zip the built app for sharing (Google Drive, AirDrop). Build with UNIVERSAL=1 first if the
## other Mac has a different chip.
zip: app
	rm -f build/Mouthful.zip
	ditto -c -k --keepParent $(APP) build/Mouthful.zip
	@echo "Share build/Mouthful.zip. On the other Mac: unzip, move Mouthful.app to Applications, right-click > Open."

## Copy the built app to /Applications
install: app
	rm -rf /Applications/Mouthful.app
	cp -R $(APP) /Applications/Mouthful.app
	@echo "Installed /Applications/Mouthful.app"

## iPhone: generate iOS/MouthfulMobile.xcodeproj and open it in Xcode (Xcode from the App Store required)
iphone: iphone-project
	@[ -d /Applications/Xcode.app ] || echo "Heads up: Xcode was not found in /Applications. Install it from the App Store and open it once."
	open iOS/MouthfulMobile.xcodeproj
	@echo ""
	@echo "In Xcode: click the blue MouthfulMobile icon at the top of the left sidebar, then for BOTH targets"
	@echo "(MouthfulMobile and MouthfulKeyboard) open Signing & Capabilities and pick your Team."
	@echo "Select your iPhone in the device menu at the top and press the Run (play) button."

## Only regenerate the iPhone project
iphone-project: $(XCODEGEN)
	cd iOS && $(abspath $(XCODEGEN)) generate

## Generate Mouthful.xcodeproj for the Mac app (optional, for people who prefer Xcode)
xcodeproj: $(XCODEGEN)
	$(abspath $(XCODEGEN)) generate
	@echo "Open Mouthful.xcodeproj and press Run."

.tools/xcodegen/bin/xcodegen:
	@echo "==> Downloading XcodeGen (one time, about 14 MB)..."
	@mkdir -p .tools
	@curl -fsSL "$(XCODEGEN_ZIP)" -o .tools/xcodegen.zip
	@rm -rf .tools/xcodegen && unzip -oq .tools/xcodegen.zip -d .tools && rm -f .tools/xcodegen.zip
	@chmod +x .tools/xcodegen/bin/xcodegen
	@xattr -dr com.apple.quarantine .tools/xcodegen 2>/dev/null || true

## Run the fast, platform-independent unit tests for the core library
test-core:
	cd MouthfulCore && swift test

clean:
	rm -rf .build build MouthfulCore/.build Mouthful.xcodeproj iOS/MouthfulMobile.xcodeproj
