APP_NAME   := URLBouncer
BUNDLE     := $(APP_NAME).app
CONTENTS   := $(BUNDLE)/Contents
MACOS_DIR  := $(CONTENTS)/MacOS
RSRC_DIR   := $(CONTENTS)/Resources
BIN_DIR    := $(shell swift build -c release --show-bin-path)

# `swift test` needs the Swift Testing framework, which lives under the active
# developer directory's Library/Developer/{Frameworks,usr/lib}. On a machine
# with only Xcode Command Line Tools installed (no full Xcode.app) that
# directory isn't on the default search/rpath, so it's passed explicitly here.
DEVELOPER_DIR      := $(shell xcode-select -p)
SWIFT_TESTING_FLAGS := -Xswiftc -F$(DEVELOPER_DIR)/Library/Developer/Frameworks \
                       -Xlinker -F$(DEVELOPER_DIR)/Library/Developer/Frameworks \
                       -Xlinker -rpath -Xlinker $(DEVELOPER_DIR)/Library/Developer/Frameworks \
                       -Xlinker -rpath -Xlinker $(DEVELOPER_DIR)/Library/Developer/usr/lib

.PHONY: all build bundle install clean test test-fast test-unit test-integration

all: bundle

build:
	swift build -c release

bundle: build
	@mkdir -p $(MACOS_DIR) $(RSRC_DIR)
	cp "$(BIN_DIR)/$(APP_NAME)" $(MACOS_DIR)/$(APP_NAME)
	@cp Info.plist $(CONTENTS)/Info.plist
	@printf 'APPL????' > $(CONTENTS)/PkgInfo
	@cp config.json $(RSRC_DIR)/config.json
	@cp AppIcon.icns $(RSRC_DIR)/AppIcon.icns
	@cp menuicon.png $(RSRC_DIR)/menuicon.png
	@cp "menuicon@2x.png" "$(RSRC_DIR)/menuicon@2x.png"
	codesign --force --sign - $(BUNDLE)
	@echo ""
	@echo "Built: $(BUNDLE)"
	@echo "Run 'make install' to copy to /Applications"

install: bundle
	@rm -rf /Applications/$(BUNDLE)
	@cp -r $(BUNDLE) /Applications/$(BUNDLE)
	codesign --force --sign - /Applications/$(BUNDLE)
	@echo ""
	@echo "Installed: /Applications/$(BUNDLE)"
	@echo ""
	@echo "Next steps:"
	@echo "  1. Launch the app: open /Applications/$(BUNDLE)"
	@echo "  2. Click the menu bar icon -> Set as Default Browser"
	@echo "     (macOS will show its own confirmation dialog - approve it there)"
	@echo "  3. Edit rules: ~/.config/urlbouncer/config.json"

# Fast, deterministic unit tests - the habitual command to run after every commit.
test-fast:
	swift test --filter URLBouncerCoreTests $(SWIFT_TESTING_FLAGS)

test-unit: test-fast

test: test-fast

# Slow/opt-in: builds the real .app and drives it end-to-end, plus launches
# whatever real browsers are installed. Never gated on for routine commits.
test-integration: bundle
	swift test --filter URLBouncerIntegrationTests $(SWIFT_TESTING_FLAGS)

clean:
	rm -rf $(BUNDLE) .build
