APP_NAME   := URLBouncer
BUNDLE     := $(APP_NAME).app
CONTENTS   := $(BUNDLE)/Contents
MACOS_DIR  := $(CONTENTS)/MacOS
RSRC_DIR   := $(CONTENTS)/Resources
VENV       := $(RSRC_DIR)/venv
PYTHON     := $(VENV)/bin/python3
PIP        := $(VENV)/bin/pip
LSREGISTER := /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

.PHONY: all bundle venv install clean

all: bundle

venv:
	python3 -m venv $(VENV)
	$(PIP) install --upgrade pip --quiet
	$(PIP) install -r requirements.txt --quiet

bundle: venv
	@mkdir -p $(MACOS_DIR) $(RSRC_DIR)/src
	@cp src/*.py $(RSRC_DIR)/src/
	@cp config.yaml $(RSRC_DIR)/config.yaml
	@cp Info.plist $(CONTENTS)/Info.plist
	@printf 'APPL????' > $(CONTENTS)/PkgInfo

	@# Shell launcher: exec replaces the shell so macOS sees the correct process name
	@printf '#!/bin/bash\nBUNDLE="$$(cd "$$(dirname "$${BASH_SOURCE[0]}")/../.." && pwd)"\nexec "$$BUNDLE/Contents/Resources/venv/bin/python3" "$$BUNDLE/Contents/Resources/src/urlbouncer.py"\n' \
		> $(MACOS_DIR)/$(APP_NAME)
	@chmod +x $(MACOS_DIR)/$(APP_NAME)

	@# Register with Launch Services so the app appears in the Default Browser picker
	$(LSREGISTER) -f $(BUNDLE)

	@echo ""
	@echo "Built: $(BUNDLE)"
	@echo ""
	@echo "Next steps:"
	@echo "  1. Run 'make install' to copy to ~/Applications"
	@echo "  2. Open System Settings > Desktop & Dock > Default web browser"
	@echo "     and select URLBouncer"

install: bundle
	@rm -rf /Applications/$(BUNDLE)
	@cp -r $(BUNDLE) /Applications/$(BUNDLE)
	$(LSREGISTER) -f /Applications/$(BUNDLE)
	@echo ""
	@echo "Installed: /Applications/$(BUNDLE)"
	@echo ""
	@echo "Next steps:"
	@echo "  1. Open System Settings > Desktop & Dock > Default web browser"
	@echo "     and select URLBouncer"
	@echo "  2. Launch the app: open /Applications/$(BUNDLE)"
	@echo "  3. Edit rules: ~/.config/urlbouncer/config.yaml"

clean:
	rm -rf $(BUNDLE)
