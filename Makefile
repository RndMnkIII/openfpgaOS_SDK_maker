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

# ── Read per-app metadata from app.conf if present ───────────────
-include src/$(APP)/app.conf

# ── Core identifiers (fallback defaults for RayTracingTheNextWeek) ─
AUTHOR   ?= RndMnkIII
SHORT    ?= raytracerTNW
PLATFORM ?= raytracertnw
CORE_ID  ?= $(AUTHOR).$(SHORT)

# ── Paths ────────────────────────────────────────────────────────
RELEASE      = build/sdk
REL_CORE     = $(RELEASE)/Cores/$(CORE_ID)
REL_ASSETS   = $(RELEASE)/Assets/$(PLATFORM)/common
REL_INSTANCE = $(RELEASE)/Assets/$(PLATFORM)/$(CORE_ID)
REL_PLATFORM = $(RELEASE)/Platforms
RUNTIME      = runtime

# ── Dist source: new apps use dist/$(SHORT)/, legacy uses dist/sdk ─
DIST_CORE    = $(or $(wildcard dist/$(SHORT)/Cores/$(CORE_ID)),dist/sdk/core)
DIST_PLATFORM = $(or $(wildcard dist/$(SHORT)/Platforms),dist/sdk/platform)

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
	@[ -d "$(DIST_CORE)" ] && cp "$(DIST_CORE)"/*.json "$(DIST_CORE)"/*.bin $(REL_CORE)/ 2>/dev/null || true
	@[ -d "$(DIST_PLATFORM)" ] && cp "$(DIST_PLATFORM)"/*.json $(REL_PLATFORM)/ 2>/dev/null || true
	@[ -d "$(DIST_PLATFORM)/_images" ] && cp "$(DIST_PLATFORM)/_images"/*.bin $(REL_PLATFORM)/_images/ 2>/dev/null || true
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
