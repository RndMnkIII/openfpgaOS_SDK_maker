# openfpgaOS SDK Makefile
#
# Usage:
#   make                    Build app, create release/
#   make APP=otra_app       Build a different app
#   make deploy             Copy release/ to Pocket SD card
#   make clean              Remove all build artifacts
#   make core               Build a standalone game core (interactive)
#   make package            Package game core into a ZIP

# ── App (override: make APP=otra_app) ────────────────────────────
APP ?= RayTracingTheNextWeek

# ── Paths ────────────────────────────────────────────────────────
CORE_ID      = RndMnkIII.raytracerTNW
PLATFORM     = raytracertnw
RELEASE      = build/sdk
REL_CORE     = $(RELEASE)/Cores/$(CORE_ID)
REL_ASSETS   = $(RELEASE)/Assets/$(PLATFORM)/common
REL_INSTANCE = $(RELEASE)/Assets/$(PLATFORM)/$(CORE_ID)
REL_PLATFORM = $(RELEASE)/Platforms
RUNTIME      = runtime

# ── Default target ───────────────────────────────────────────────
all: app tools release

# ── Build app ────────────────────────────────────────────────────
app:
	@echo "Building $(APP)..."
	$(MAKE) -C src/$(APP) SDK_DIR=$(CURDIR)/src/sdk
	@[ -f src/$(APP)/app.elf ] && mv src/$(APP)/app.elf src/$(APP)/$(APP).elf 2>/dev/null || true

# ── Create release/ directory ────────────────────────────────────
release: app
	@echo "Creating release/..."
	@mkdir -p $(REL_CORE) $(REL_ASSETS) $(REL_INSTANCE) $(REL_PLATFORM)/_images
	@cp $(RUNTIME)/bitstream.rbf_r $(REL_CORE)/
	@cp $(RUNTIME)/loader.bin $(REL_CORE)/
	@[ -d dist/sdk/core ] && cp dist/sdk/core/*.json dist/sdk/core/*.bin $(REL_CORE)/ 2>/dev/null || true
	@[ -d dist/sdk/platform ] && cp dist/sdk/platform/*.json $(REL_PLATFORM)/ 2>/dev/null || true
	@[ -d dist/sdk/platform/_images ] && cp dist/sdk/platform/_images/*.bin $(REL_PLATFORM)/_images/ 2>/dev/null || true
	@cp $(RUNTIME)/os.bin $(REL_ASSETS)/
	@cp src/$(APP)/$(APP).elf $(REL_ASSETS)/
	@find src/$(APP) -maxdepth 1 \( -name "*.mid" -o -name "*.wav" -o -name "*.dat" -o -name "*.png" \) \
		-exec cp {} "$(REL_ASSETS)/" \; 2>/dev/null || true
	@[ -f src/$(APP)/$(APP).json ] && cp src/$(APP)/$(APP).json $(REL_INSTANCE)/ || true
	@echo "Release ready: $(RELEASE)/"

# ── Deploy to SD card ────────────────────────────────────────────
deploy: release
	@./scripts/deploy.sh

# ── Build host tools ─────────────────────────────────────────────
tools:
	$(MAKE) -C src/tools/phdp

# ── Clean ────────────────────────────────────────────────────────
clean:
	$(MAKE) -C src/$(APP) clean
	$(MAKE) -C src/tools/phdp clean
	rm -rf build releases

# ── Core packaging ───────────────────────────────────────────────
core:
	./create_app.sh

package:
	./scripts/package.sh

.PHONY: all app tools release deploy clean core package
