VERSION ?= 0.0.0-dev
ARCHS ?= arm64 x86_64
APP := build/ClaudeVimium.app
SOURCES := app/Hints.swift app/main.swift

.PHONY: app test clean

app:
	rm -rf $(APP) build/obj
	mkdir -p $(APP)/Contents/MacOS build/obj
	for arch in $(ARCHS); do \
	  swiftc -O -target $$arch-apple-macos13.0 $(SOURCES) -o build/obj/ClaudeVimium-$$arch || exit 1; \
	done
	lipo -create build/obj/ClaudeVimium-* -output $(APP)/Contents/MacOS/ClaudeVimium
	sed 's/@VERSION@/$(VERSION)/g' app/Info.plist > $(APP)/Contents/Info.plist
	plutil -lint $(APP)/Contents/Info.plist
	codesign --force --sign - $(APP)

test:
	for t in test/*.test.js; do node $$t || exit 1; done
	sh test/cli.test.sh
	mkdir -p build
	swiftc app/Hints.swift test/hints/main.swift -o build/hints-test
	build/hints-test

clean:
	rm -rf build
