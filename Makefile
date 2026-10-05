VERSION ?= 0.0.0-dev
ARCHS ?= arm64 x86_64
APP := build/Hintvim.app
SOURCES := app/Hints.swift app/main.swift

.PHONY: app icon test clean

app:
	rm -rf $(APP) build/obj
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources build/obj
	for arch in $(ARCHS); do \
	  swiftc -O -target $$arch-apple-macos13.0 $(SOURCES) -o build/obj/Hintvim-$$arch || exit 1; \
	done
	lipo -create build/obj/Hintvim-* -output $(APP)/Contents/MacOS/Hintvim
	sed 's/@VERSION@/$(VERSION)/g' app/Info.plist > $(APP)/Contents/Info.plist
	plutil -lint $(APP)/Contents/Info.plist
	cp app/AppIcon.icns $(APP)/Contents/Resources/
	codesign --force --sign - $(APP)

# Regenerates app/AppIcon.icns from the 1024 px master; run it after changing docs/assets/icon.png.
# Keep the master's tile on Apple's grid (824 px rounded square, 100 px margin):
# macOS 26 shrinks an icon that is off it onto a grey tile.
icon:
	rm -rf build/AppIcon.iconset && mkdir -p build/AppIcon.iconset
	for s in 16 32 128 256 512; do \
	  sips -z $$s $$s docs/assets/icon.png --out build/AppIcon.iconset/icon_$${s}x$$s.png >/dev/null && \
	  sips -z $$((s * 2)) $$((s * 2)) docs/assets/icon.png --out build/AppIcon.iconset/icon_$${s}x$${s}@2x.png >/dev/null || exit 1; \
	done
	iconutil -c icns build/AppIcon.iconset -o app/AppIcon.icns

test:
	for t in test/*.test.js; do node $$t || exit 1; done
	sh test/cli.test.sh
	sh test/doctor.test.sh
	sh test/publish-tap.test.sh
	mkdir -p build
	swiftc app/Hints.swift test/hints/main.swift -o build/hints-test
	build/hints-test

clean:
	rm -rf build
