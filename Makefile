APP := Browspick
BIN := .build/release/$(APP)
APP_DIR := $(APP).app
# Self-signed cert in a dedicated keychain — a stable signing identity is required
# so TCC grants (profile file access) survive rebuilds. Adhoc signing changes the
# cdhash every build, which silently invalidates Files & Folders permissions.
KEYCHAIN := $(HOME)/Library/Keychains/browspick-signing.keychain-db
IDENTITY := Browspick Local Signing
KEYCHAIN_PASSWORD := $(BROWSPICK_KC_PASS)

.PHONY: build bundle install run test icon clean

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
	@if [ ! -f Resources/AppIcon.icns ]; then swift Scripts/make-icon.swift; fi

install: bundle
	rm -rf /Applications/$(APP).app
	cp -R $(APP_DIR) /Applications/
	@echo "Installed to /Applications/$(APP).app"

run: bundle
	open $(APP_DIR)

test:
	swift run CoreChecks

clean:
	rm -rf .build $(APP_DIR)
