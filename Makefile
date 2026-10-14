APP_NAME    := HideHidden
BUNDLE_ID   := com.mythofmeat.HideHidden
# Release builds get this from the formula; the release workflow keeps the two in step.
VERSION     := 0.1.0
INSTALL_DIR ?= /Applications

# Signing with a stable identity keeps the Accessibility grant across rebuilds.
# Without one we fall back to ad-hoc signing, and macOS will ask again after every rebuild.
SIGN_NAME     ?= HideHidden Signing
SIGN_IDENTITY ?= $(shell security find-identity -p codesigning 2>/dev/null | grep -q '"$(SIGN_NAME)"' && echo '$(SIGN_NAME)' || echo -)

APP := build/$(APP_NAME).app

.PHONY: all build app run install uninstall logs clean

all: app

# Homebrew builds inside its own sandbox, where SwiftPM must be told not to start another one.
SWIFT_BUILD_FLAGS ?=

build:
	swift build -c release $(SWIFT_BUILD_FLAGS)

app: build
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	cp .build/release/$(APP_NAME) $(APP)/Contents/MacOS/$(APP_NAME)
	sed -e 's/$$(APP_NAME)/$(APP_NAME)/g' -e 's/$$(BUNDLE_ID)/$(BUNDLE_ID)/g' -e 's/$$(VERSION)/$(VERSION)/g' \
		Info.plist > $(APP)/Contents/Info.plist
	codesign --force --sign "$(SIGN_IDENTITY)" --identifier $(BUNDLE_ID) $(APP)
	@echo "Built $(APP) (signed with: $(SIGN_IDENTITY))"

run: app
	@pkill -x $(APP_NAME) || true
	open $(APP)

install: app
	@pkill -x $(APP_NAME) || true
	rm -rf "$(INSTALL_DIR)/$(APP_NAME).app"
	cp -R $(APP) "$(INSTALL_DIR)/"
	open "$(INSTALL_DIR)/$(APP_NAME).app"
	@echo "Installed to $(INSTALL_DIR)/$(APP_NAME).app"

uninstall:
	@pkill -x $(APP_NAME) || true
	rm -rf "$(INSTALL_DIR)/$(APP_NAME).app"
	-tccutil reset Accessibility $(BUNDLE_ID)

logs:
	log stream --predicate 'subsystem == "$(BUNDLE_ID)"' --style compact --level info

clean:
	rm -rf .build build
