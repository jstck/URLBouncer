APP_NAME   := URLBouncer
BUNDLE     := $(APP_NAME).app
CONTENTS   := $(BUNDLE)/Contents
MACOS_DIR  := $(CONTENTS)/MacOS
RSRC_DIR   := $(CONTENTS)/Resources
LSREGISTER := /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

.PHONY: all bundle install clean

all: bundle

bundle:
	@mkdir -p $(MACOS_DIR) $(RSRC_DIR)
	swiftc -O -o $(MACOS_DIR)/$(APP_NAME) src/main.swift
	@cp Info.plist $(CONTENTS)/Info.plist
	@printf 'APPL????' > $(CONTENTS)/PkgInfo
	@cp config.json $(RSRC_DIR)/config.json
	codesign --force --sign - $(BUNDLE)
	$(LSREGISTER) -f $(BUNDLE)
	@echo ""
	@echo "Built: $(BUNDLE)"
	@echo "Run 'make install' to copy to /Applications"

install: bundle
	@rm -rf /Applications/$(BUNDLE)
	@cp -r $(BUNDLE) /Applications/$(BUNDLE)
	codesign --force --sign - /Applications/$(BUNDLE)
	$(LSREGISTER) -f /Applications/$(BUNDLE)
	@echo ""
	@echo "Installed: /Applications/$(BUNDLE)"
	@echo ""
	@echo "Next steps:"
	@echo "  1. Open System Settings > Desktop & Dock > Default web browser"
	@echo "     and select URLBouncer"
	@echo "  2. Launch the app: open /Applications/$(BUNDLE)"
	@echo "  3. Edit rules: ~/.config/urlbouncer/config.json"

clean:
	rm -rf $(BUNDLE)
