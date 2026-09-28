# Dictum – developer shortcuts. Run from this directory.
APP = build/Dictum.app

.PHONY: app run install xcodeproj test-core clean

## Build a release .app bundle into build/
app:
	./scripts/build-app.sh

## Build and launch
run: app
	open $(APP)

## Copy the built app to /Applications
install: app
	rm -rf /Applications/Dictum.app
	cp -R $(APP) /Applications/Dictum.app
	@echo "Installed /Applications/Dictum.app"

## Generate Dictum.xcodeproj (requires: brew install xcodegen)
xcodeproj:
	xcodegen generate
	@echo "Open Dictum.xcodeproj and press Run."

## Run the fast, platform-independent unit tests for the core library
test-core:
	cd DictumCore && swift test

clean:
	rm -rf .build build DictumCore/.build Dictum.xcodeproj
