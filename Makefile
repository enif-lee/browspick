APP := Browspick
BIN := .build/release/$(APP)
APP_DIR := $(APP).app
# Self-signed cert in a dedicated keychain — a stable signing identity is required
# so TCC grants (profile file access) survive rebuilds. Adhoc signing changes the
# cdhash every build, which silently invalidates Files & Folders permissions.
KEYCHAIN := $(HOME)/Library/Keychains/browspick-signing.keychain-db
IDENTITY := Browspick Local Signing
# Signing keychain unlock password — resolved from the login keychain item
# "browspick-signing" (created by Scripts/setup-signing.sh), or set
# BROWSPICK_KEYCHAIN_PASSWORD in the environment to override.
KEYCHAIN_PASSWORD ?= $(shell security find-generic-password -s browspick-signing -w 2>/dev/null || echo "$(BROWSPICK_KEYCHAIN_PASSWORD)")

.PHONY: build bundle install run dmg extension test icon clean

build:
	swift build -c release

bundle: build icon
	rm -rf $(APP_DIR)
	mkdir -p $(APP_DIR)/Contents/MacOS $(APP_DIR)/Contents/Resources
	cp $(BIN) $(APP_DIR)/Contents/MacOS/$(APP)
	cp Resources/Info.plist $(APP_DIR)/Contents/Info.plist
	@if [ -f Resources/AppIcon.icns ]; then cp Resources/AppIcon.icns $(APP_DIR)/Contents/Resources/; fi
	security unlock-keychain -p "$(KEYCHAIN_PASSWORD)" "$(KEYCHAIN)" 2>/dev/null || true
	codesign --keychain "$(KEYCHAIN)" --force --deep --sign "$(IDENTITY)" $(APP_DIR)
	@echo "Built $(APP_DIR)"

icon:
	rm -rf Resources/AppIcon.iconset
	mkdir -p Resources/AppIcon.iconset
	for s in 16 32 128 256 512; do \
		sips -z $$s $$s Resources/icon.png --out Resources/AppIcon.iconset/icon_$${s}x$${s}.png >/dev/null; \
		sips -z $$((s*2)) $$((s*2)) Resources/icon.png --out Resources/AppIcon.iconset/icon_$${s}x$${s}@2x.png >/dev/null; \
	done
	iconutil -c icns Resources/AppIcon.iconset -o Resources/AppIcon.icns

install: bundle
	rm -rf /Applications/$(APP).app
	cp -R $(APP_DIR) /Applications/
	@echo "Installed to /Applications/$(APP).app"

run: bundle
	open $(APP_DIR)

VERSION ?= 0.0.3
dmg: bundle
	rm -rf .build/dmg-staging .build/$(APP)-$(VERSION).dmg
	mkdir -p .build/dmg-staging
	cp -R $(APP_DIR) .build/dmg-staging/
	ln -s /Applications .build/dmg-staging/Applications
	hdiutil create -volname $(APP) -srcfolder .build/dmg-staging \
		-ov -format UDZO .build/$(APP)-$(VERSION).dmg
	@echo "Built .build/$(APP)-$(VERSION).dmg"

extension:
	rm -f .build/$(APP)-chrome-$(VERSION).zip
	cd Extensions/chrome && zip -qr ../../.build/$(APP)-chrome-$(VERSION).zip .
	@echo "Built .build/$(APP)-chrome-$(VERSION).zip"
	@echo "Dev install: chrome://extensions → Developer mode → Load unpacked → Extensions/chrome"

test:
	swift run CoreChecks

clean:
	rm -rf .build $(APP_DIR)
