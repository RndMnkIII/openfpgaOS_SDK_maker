#!/usr/bin/env bash
# ── create_app.sh ─────────────────────────────────────────────────
# Unified openfpgaOS SDK Application Creator
#
# Merges create_app.sh + scripts/customize.sh into a single workflow:
#   Phase 1 — Collect app metadata (interactive or via flags)
#   Phase 2 — Create src/<app>/ with stub main.c and Makefile
#   Phase 3 — Compile the application ELF
#   Phase 4 — Generate app.conf, core.json, data.json, platform.json
#              and copy runtime files to the output directory
#
# Usage (interactive):
#   ./create_app.sh
#
# Usage (non-interactive / batch):
#   ./create_app.sh --batch \
#       --name "C++ Raytracer The Next Week" \
#       --short RaytracerTNW \
#       --author RndMnkIII \
#       --platform raytracertnw \
#       --description "Ray tracing demo app" \
#       --version 0.1 \
#       --date 2026-03-29 \
#       --output dist/RaytracerTNW
#
# Run ./create_app.sh --help for the full option list.
# ──────────────────────────────────────────────────────────────────
set -e

# ── Color helpers ─────────────────────────────────────────────────
RED='\033[0;31m'
GRN='\033[0;32m'
YLW='\033[0;33m'
BLU='\033[0;34m'
CYN='\033[0;36m'
RST='\033[0m'

info()    { echo -e "${BLU}[info]${RST}  $*"; }
ok()      { echo -e "${GRN}[ok]${RST}    $*"; }
warn()    { echo -e "${YLW}[warn]${RST}  $*"; }
error()   { echo -e "${RED}[error]${RST} $*" >&2; exit 1; }
header()  { echo -e "\n${CYN}══ $* ══${RST}"; }

# ── Defaults ──────────────────────────────────────────────────────
NAME=""
SHORT=""
AUTHOR="ThinkElastic"
PLATFORM=""
DESCRIPTION=""
VERSION="1.0.0"
DATE=$(date +%Y-%m-%d)
OUTPUT=""
LIB_NAME=""
DATA_FILES=()
SAVES=10
SAVE_SIZE="0x40000"
ICON=""
BATCH=0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNTIME="$SCRIPT_DIR/runtime"
BITSTREAM="$RUNTIME/bitstream.rbf_r"
OS_BIN="$RUNTIME/os.bin"
LOADER="$RUNTIME/loader.bin"

# ── Parse command-line flags ──────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        --batch)        BATCH=1; shift ;;
        --name)         [[ -n "$2" ]] || error "--name requires a value"; NAME="$2"; shift 2 ;;
        --short)        [[ -n "$2" ]] || error "--short requires a value"; SHORT="$2"; shift 2 ;;
        --author)       [[ -n "$2" ]] || error "--author requires a value"; AUTHOR="$2"; shift 2 ;;
        --platform)     [[ -n "$2" ]] || error "--platform requires a value"; PLATFORM="$2"; shift 2 ;;
        --description)  [[ -n "$2" ]] || error "--description requires a value"; DESCRIPTION="$2"; shift 2 ;;
        --version)      [[ -n "$2" ]] || error "--version requires a value"; VERSION="$2"; shift 2 ;;
        --date)         [[ -n "$2" ]] || error "--date requires a value"; DATE="$2"; shift 2 ;;
        --data)         [[ -n "$2" ]] || error "--data requires a path"; DATA_FILES+=("$2"); shift 2 ;;
        --output)       [[ -n "$2" ]] || error "--output requires a directory"; OUTPUT="$2"; shift 2 ;;
        --lib)          [[ -n "$2" ]] || error "--lib requires a name"; LIB_NAME="$2"; shift 2 ;;
        --saves)        [[ -n "$2" ]] || error "--saves requires a number"; SAVES="$2"; shift 2 ;;
        --save-size)    [[ -n "$2" ]] || error "--save-size requires a value"; SAVE_SIZE="$2"; shift 2 ;;
        --icon)         [[ -n "$2" ]] || error "--icon requires a path"; ICON="$2"; shift 2 ;;
        --bitstream)    [[ -n "$2" ]] || error "--bitstream requires a path"; BITSTREAM="$2"; shift 2 ;;
        --os-bin)       [[ -n "$2" ]] || error "--os-bin requires a path"; OS_BIN="$2"; shift 2 ;;
        --loader)       [[ -n "$2" ]] || error "--loader requires a path"; LOADER="$2"; shift 2 ;;
        -h|--help)
            echo "Usage: $0 [--batch] [options]"
            echo ""
            echo "  Interactive mode (default) prompts for each parameter."
            echo "  Use --batch for scripted/CI usage with all parameters via flags."
            echo ""
            echo "Metadata flags:"
            echo "  --name NAME           Full application display name"
            echo "  --short SHORT         Short name, no spaces (used as directory name)"
            echo "  --author AUTHOR       Core author identifier [ThinkElastic]"
            echo "  --platform PLATFORM   Platform ID (lowercase, no spaces)"
            echo "  --description DESC    Application-specific description"
            echo "  --version VERSION     Initial version string [1.0.0]"
            echo "  --date DATE           Release date YYYY-MM-DD [today]"
            echo "  --data PATH           Additional data file (repeatable)"
            echo "  --output DIR          Output directory [dist/<SHORT>]"
            echo ""
            echo "Optional source/library flags:"
            echo "  --lib NAME            Create a bundled static library src/<app>/<lib>/"
            echo ""
            echo "Runtime/packaging flags:"
            echo "  --saves N             Number of save slots [10]"
            echo "  --save-size HEX       Max save size per slot [0x40000]"
            echo "  --icon PATH           Core icon file (.bin)"
            echo "  --bitstream PATH      Bitstream file [runtime/bitstream.rbf_r]"
            echo "  --os-bin PATH         OS binary [runtime/os.bin]"
            echo "  --loader PATH         Chip32 loader [runtime/loader.bin]"
            exit 0
            ;;
        *) error "Unknown option: $1" ;;
    esac
done

# ── Generate platform JSON ────────────────────────────────────────
generate_platform_json() {
    local dest="$1"
    cat > "$dest" << PLATJSON
{
    "platform": {
        "category": "Computer",
        "name": "$NAME",
        "year": $(date +%Y),
        "manufacturer": "$AUTHOR"
    }
}
PLATJSON
    ok "Generated platform: ${PLATFORM}.json"
}

# ── Locate SDK ────────────────────────────────────────────────────
SDK_ABS="$(find "$SCRIPT_DIR/src" -maxdepth 2 -name "sdk.mk" 2>/dev/null \
    | head -1 | xargs -I{} dirname {} 2>/dev/null)"
[[ -n "$SDK_ABS" ]] || error "sdk.mk not found under $SCRIPT_DIR/src/. Are you in the project root?"

# ── Derive short name helper ──────────────────────────────────────
derive_short() {
    echo "$1" | sed 's/[^a-zA-Z0-9]//g'
}

# Regex for valid short names and library names (letters, digits, underscores)
VALID_ID_PATTERN='^[a-zA-Z0-9_]+$'

# ── Prompt helper (with optional default) ─────────────────────────
ask_prompt() {
    local prompt="$1"
    local default="$2"
    local result
    if [[ -n "$default" ]]; then
        read -rp "${CYN}[?]${RST}     $prompt [$default]: " result
        echo "${result:-$default}"
    else
        read -rp "${CYN}[?]${RST}     $prompt: " result
        echo "$result"
    fi
}

# ── Validate file exists ──────────────────────────────────────────
check_file() {
    local path="$1"
    local label="$2"
    if [[ -f "$path" ]]; then
        local size
        size=$(wc -c < "$path" | tr -d ' ')
        ok "$label: $path ($size bytes)"
        return 0
    else
        warn "$label: $path not found"
        return 1
    fi
}

# ══════════════════════════════════════════════════════════════════
# PHASE 1 — Collect metadata
# ══════════════════════════════════════════════════════════════════
header "Phase 1 — App Metadata"

if [[ $BATCH -eq 0 ]]; then
    NAME=$(ask_prompt "Full application name (e.g. \"C++ Raytracer The Next Week\")" "$NAME")
    [[ -z "$NAME" ]] && error "Name is required."

    default_short=$(derive_short "$NAME")
    SHORT=$(ask_prompt "Short name, no spaces (e.g. \"RaytracerTNW\")" "${SHORT:-$default_short}")
    [[ -z "$SHORT" ]] && error "Short name is required."

    AUTHOR=$(ask_prompt "Author identifier (e.g. \"RndMnkIII\")" "$AUTHOR")

    [[ -z "$PLATFORM" ]] && PLATFORM=$(echo "$SHORT" | tr '[:upper:]' '[:lower:]')
    PLATFORM=$(ask_prompt "Platform ID, lowercase (e.g. \"raytracertnw\")" "$PLATFORM")

    DESCRIPTION=$(ask_prompt "Application description" "${DESCRIPTION:-$NAME on openfpgaOS}")

    VERSION=$(ask_prompt "Initial version" "$VERSION")
    DATE=$(ask_prompt "Release date (YYYY-MM-DD)" "$DATE")

    echo
    echo "Data files (one per line, empty line to finish):"
    DATA_FILES=()
    idx=1
    while true; do
        df=$(ask_prompt "  [$idx] data file path" "")
        [[ -z "$df" ]] && break
        if [[ -f "$df" ]]; then
            ok "Found $(basename "$df")"
            DATA_FILES+=("$df")
            idx=$((idx + 1))
        else
            warn "$df not found, skipping"
        fi
    done
    echo "  ${#DATA_FILES[@]} data file(s) added."

    echo
    SAVES=$(ask_prompt "Number of save slots (0-10)" "$SAVES")
    if [[ $SAVES -gt 0 ]]; then
        SAVE_SIZE=$(ask_prompt "Max save size per slot" "$SAVE_SIZE")
    fi

    ICON=$(ask_prompt "Core icon path (.bin, optional — press Enter to skip)" "$ICON")
    OUTPUT=$(ask_prompt "Output directory" "${OUTPUT:-dist/$SHORT}")

    # Lib prompt
    read -rp "${CYN}[?]${RST}     Include a bundled static library? [y/N] " ans
    if [[ "$ans" =~ ^[yY]$ ]]; then
        read -rp "${CYN}[?]${RST}     Library name: " LIB_NAME
        [[ "$LIB_NAME" =~ $VALID_ID_PATTERN ]] || \
            error "Library name may only contain letters, digits, and underscores"
    fi

    # Summary
    echo
    echo -e "${CYN}--- Summary ---${RST}"
    echo "  Name:        $NAME"
    echo "  Short:       $SHORT"
    echo "  Author:      $AUTHOR"
    echo "  Platform:    $PLATFORM"
    echo "  Description: $DESCRIPTION"
    echo "  Version:     $VERSION"
    echo "  Date:        $DATE"
    for df in "${DATA_FILES[@]}"; do echo "  Data:        $(basename "$df")"; done
    echo "  Saves:       $SAVES × $SAVE_SIZE"
    echo "  Output:      $OUTPUT"
    [[ -n "$LIB_NAME" ]] && echo "  Library:     $LIB_NAME"
    echo

    read -rp "Proceed? [Y/n] " confirm
    [[ "$confirm" =~ ^[Nn] ]] && { echo "Aborted."; exit 0; }
fi

# ── Validate required inputs ──────────────────────────────────────
[[ -z "$NAME" ]]    && error "--name is required in batch mode"
[[ -z "$SHORT" ]]   && SHORT=$(derive_short "$NAME")
[[ -z "$PLATFORM" ]] && PLATFORM=$(echo "$SHORT" | tr '[:upper:]' '[:lower:]')
[[ -z "$OUTPUT" ]]  && OUTPUT="dist/$SHORT"
[[ -z "$DESCRIPTION" ]] && DESCRIPTION="$NAME on openfpgaOS"
[[ "$SHORT" =~ $VALID_ID_PATTERN ]] || \
    error "Short name may only contain letters, digits, and underscores: '$SHORT'"
[[ -n "$LIB_NAME" ]] && { [[ "$LIB_NAME" =~ $VALID_ID_PATTERN ]] || \
    error "Library name may only contain letters, digits, and underscores: '$LIB_NAME'"; }

SNAME=$(echo "$SHORT" | tr '[:upper:]' '[:lower:]')
CORE_ID="${AUTHOR}.${SHORT}"
APP_DIR="$SCRIPT_DIR/src/$SNAME"
SDK_REL="$(python3 -c "import os; print(os.path.relpath('$SDK_ABS', '$APP_DIR'))")"
LIB_SDK_REL=""
[[ -n "$LIB_NAME" ]] && \
    LIB_SDK_REL="$(python3 -c "import os; print(os.path.relpath('$SDK_ABS', '$APP_DIR/$LIB_NAME'))")"
ELF_NAME="${SNAME}.elf"

info "App source : src/$SNAME/"
info "Core ID   : $CORE_ID"
info "Platform  : $PLATFORM"
info "Output    : $OUTPUT"

# ══════════════════════════════════════════════════════════════════
# PHASE 2 — Create directory structure
# ══════════════════════════════════════════════════════════════════
header "Phase 2 — Directory Structure"

if [[ ! -d "$APP_DIR" ]]; then
    mkdir -p "$APP_DIR"
    [[ -n "$LIB_NAME" ]] && mkdir -p "$APP_DIR/$LIB_NAME/include" "$APP_DIR/$LIB_NAME/src"

    # ── Makefile (with lib) ───────────────────────────────────────
    if [[ -n "$LIB_NAME" ]]; then
cat > "$APP_DIR/Makefile" << MAKEFILE
# src/$SNAME/Makefile

SDK_DIR = $SDK_REL

SRCS     = \$(wildcard *.c)
SRCS_CXX = \$(wildcard *.cpp)

LIB     = $LIB_NAME/lib${LIB_NAME}.a
LIB_INC = -I$LIB_NAME/include

include \$(SDK_DIR)/sdk.mk
AR = \$(CROSS)ar

ALL_CFLAGS   += \$(LIB_INC)
ALL_CXXFLAGS += \$(LIB_INC)

\$(LIB):
	\$(MAKE) -C $LIB_NAME SDK_DIR=\$(CURDIR)/$SDK_REL

\$(CRT_DIR)/start.o: \$(CRT_DIR)/start.S
	\$(AS) \$(ASFLAGS) -c -o \$@ \$<

app.elf: \$(OBJS) \$(LIB) \$(APP_LD)
	\$(LD) \$(ALL_LDFLAGS) -o \$@ \$(OBJS) \$(LIB) \$(LIBGCC)

all: \$(LIB) app.elf
	\$(SIZE) app.elf

clean: sdk-clean
	\$(MAKE) -C $LIB_NAME clean

.PHONY: all clean
MAKEFILE
    else
# ── Makefile (no lib) ─────────────────────────────────────────────
cat > "$APP_DIR/Makefile" << MAKEFILE
# src/$SNAME/Makefile

SDK_DIR = $SDK_REL

SRCS     = \$(wildcard *.c)
SRCS_CXX = \$(wildcard *.cpp)

include \$(SDK_DIR)/sdk.mk

\$(CRT_DIR)/start.o: \$(CRT_DIR)/start.S
	\$(AS) \$(ASFLAGS) -c -o \$@ \$<

app.elf: \$(OBJS) \$(APP_LD)
	\$(LD) \$(ALL_LDFLAGS) -o \$@ \$(OBJS) \$(LIBGCC)

all: app.elf
	\$(SIZE) app.elf

clean: sdk-clean

.PHONY: all clean
MAKEFILE
    fi
    ok "src/$SNAME/Makefile"

    # ── Lib Makefile ──────────────────────────────────────────────
    if [[ -n "$LIB_NAME" ]]; then
cat > "$APP_DIR/$LIB_NAME/Makefile" << MAKEFILE
# src/$SNAME/$LIB_NAME/Makefile

SDK_DIR = $LIB_SDK_REL

SRCS     = src/module1.c src/module2.c
SRCS_CXX = src/module3.cpp
OBJS     = \$(SRCS:.c=.o) \$(SRCS_CXX:.cpp=.o)
LIB      = lib${LIB_NAME}.a

include \$(SDK_DIR)/sdk.mk
AR = \$(CROSS)ar

\$(LIB): \$(OBJS)
	\$(AR) rcs \$@ \$^

src/%.o: src/%.c
	\$(CC) \$(ALL_CFLAGS) -I include -c -o \$@ \$<

src/%.o: src/%.cpp
	\$(CXX) \$(ALL_CXXFLAGS) -I include -c -o \$@ \$<

clean:
	rm -f \$(OBJS) \$(LIB)

.PHONY: clean
MAKEFILE
        ok "src/$SNAME/$LIB_NAME/Makefile"

        # Lib header stub
        cat > "$APP_DIR/$LIB_NAME/include/${LIB_NAME}.h" << HH
// src/$SNAME/$LIB_NAME/include/${LIB_NAME}.h
#pragma once

void ${LIB_NAME}_init(void);
void ${LIB_NAME}_update(void);
HH
        ok "src/$SNAME/$LIB_NAME/include/${LIB_NAME}.h"

        # Lib source stubs
        cat > "$APP_DIR/$LIB_NAME/src/module1.c" << CC
// src/$SNAME/$LIB_NAME/src/module1.c
#include "${LIB_NAME}.h"

void ${LIB_NAME}_init(void) {
    /* TODO: initialization */
}
CC
        cat > "$APP_DIR/$LIB_NAME/src/module2.c" << CC
// src/$SNAME/$LIB_NAME/src/module2.c
#include "${LIB_NAME}.h"

void ${LIB_NAME}_update(void) {
    /* TODO: per-frame logic */
}
CC
        cat > "$APP_DIR/$LIB_NAME/src/module3.cpp" << CPP
// src/$SNAME/$LIB_NAME/src/module3.cpp
#include "${LIB_NAME}.h"

/* TODO: C++ module for $LIB_NAME */
CPP
        ok "src/$SNAME/$LIB_NAME/src/ (module stubs)"
    fi

    # ── Stub main.c ───────────────────────────────────────────────
    LIB_INCLUDE=""
    [[ -n "$LIB_NAME" ]] && LIB_INCLUDE="#include \"${LIB_NAME}.h\""
    cat > "$APP_DIR/main.c" << STUB
/*
 * $NAME — openfpgaOS stub app
 *
 * Edit this file and run: make -C src/$SNAME
 */
#include "of.h"
#include <stdio.h>
#include <string.h>
$LIB_INCLUDE

int main(void) {
    of_video_init();

    /* Simple grayscale palette */
    for (int i = 0; i < 256; i++)
        of_video_palette(i, (i << 16) | (i << 8) | i);

    /* Gradient demo */
    uint8_t *fb = of_video_surface();
    for (int y = 0; y < 240; y++)
        memset(&fb[y * 320], (uint8_t)y, 320);

    of_video_flip();

    printf("$NAME\\n");
    printf("Press any button...\\n");

    while (1) {
        of_input_poll();
        if (of_btn(OF_BTN_MENU))
            break;
        of_delay_ms(16);
    }

    return 0;
}
STUB
    ok "src/$SNAME/main.c"
else
    ok "App source already exists: src/$SNAME/ (skipping stub creation)"
fi

# ── Create output directory ───────────────────────────────────────
mkdir -p "$OUTPUT"
ok "Output directory: $OUTPUT"

# ══════════════════════════════════════════════════════════════════
# PHASE 3 — Compile the ELF
# ══════════════════════════════════════════════════════════════════
header "Phase 3 — Compile"

info "Building ELF from src/$SNAME/ ..."
if make -C "$APP_DIR"; then
    # Rename app.elf → <sname>.elf
    if [[ -f "$APP_DIR/app.elf" ]]; then
        mv "$APP_DIR/app.elf" "$APP_DIR/$ELF_NAME"
    fi
    if [[ -f "$APP_DIR/$ELF_NAME" ]]; then
        ok "Built $ELF_NAME"
    else
        error "Compilation succeeded but $ELF_NAME not found in src/$SNAME/"
    fi
else
    error "Compilation failed — fix errors in src/$SNAME/ then re-run"
fi
ELF="$APP_DIR/$ELF_NAME"

# ── Check required runtime files ─────────────────────────────────
echo
info "Checking runtime files..."
errors=0
check_file "$ELF"        "ELF"        || errors=1
check_file "$BITSTREAM"  "Bitstream"  || errors=$((errors + 1))
check_file "$OS_BIN"     "os.bin"     || errors=$((errors + 1))
check_file "$LOADER"     "loader.bin" || errors=$((errors + 1))
[[ $errors -ne 0 ]] && warn "$errors runtime file(s) missing — dist layout may be incomplete"

# ══════════════════════════════════════════════════════════════════
# PHASE 4 — Metadata and distribution layout
# ══════════════════════════════════════════════════════════════════
header "Phase 4 — Metadata & Distribution"

# ── app.conf ─────────────────────────────────────────────────────
APP_CONF="$APP_DIR/app.conf"
cat > "$APP_CONF" << CONF
NAME=$NAME
SHORT=$SHORT
AUTHOR=$AUTHOR
PLATFORM=$PLATFORM
DESCRIPTION=$DESCRIPTION
VERSION=$VERSION
DATE=$DATE
CONF
ok "src/$SNAME/app.conf"

# ── Distribution directory structure ─────────────────────────────
CORE_DIR="$OUTPUT/Cores/$CORE_ID"
ASSETS_COMMON="$OUTPUT/Assets/$PLATFORM/common"
ASSETS_INSTANCES="$OUTPUT/Assets/$PLATFORM/$CORE_ID"
PLATFORMS_DIR="$OUTPUT/Platforms"

mkdir -p "$CORE_DIR" "$ASSETS_COMMON" "$ASSETS_INSTANCES" "$PLATFORMS_DIR/_images"

# ── core.json ─────────────────────────────────────────────────────
if [[ -f "$CORE_DIR/core.json" ]]; then
    ok "core.json already exists, skipping"
else
cat > "$CORE_DIR/core.json" << ENDJSON
{
    "core": {
        "magic": "APF_VER_1",
        "metadata": {
            "platform_ids": ["$PLATFORM"],
            "shortname": "$SHORT",
            "description": "$DESCRIPTION",
            "author": "$AUTHOR",
            "url": "",
            "version": "$VERSION",
            "date_release": "$DATE"
        },
        "framework": {
            "target_product": "Analogue Pocket",
            "version_required": "2.2",
            "sleep_supported": false,
            "dock": { "supported": true, "analog_output": false },
            "hardware": { "link_port": true, "cartridge_adapter": 0 }
        },
        "cores": [
            { "name": "default", "id": 0, "filename": "bitstream.rbf_r", "chip32_vm": "loader.bin" }
        ]
    }
}
ENDJSON
    ok "Generated core.json"
fi

# ── data.json ─────────────────────────────────────────────────────
if [[ -f "$CORE_DIR/data.json" ]]; then
    ok "data.json already exists, skipping"
else
DATA_SLOTS='[
            {
                "id": 1,
                "name": "OS Binary",
                "required": false,
                "parameters": 0,
                "filename": "os.bin",
                "extensions": ["bin"],
                "deferload": true
            },
            {
                "id": 2,
                "name": "Application",
                "required": false,
                "parameters": 0,
                "filename": "'"$ELF_NAME"'",
                "extensions": ["elf"],
                "deferload": true
            }'

# Additional data file slots (ids 3–6)
slot_id=3
for df in "${DATA_FILES[@]}"; do
    ext="${df##*.}"
    dfname=$(basename "$df")
    DATA_SLOTS="$DATA_SLOTS,"'
            {
                "id": '"$slot_id"',
                "name": "Data '"$((slot_id - 2))"'",
                "required": false,
                "parameters": 0,
                "filename": "'"$dfname"'",
                "extensions": ["'"$ext"'"],
                "deferload": true
            }'
    slot_id=$((slot_id + 1))
    if [[ $slot_id -gt 6 ]]; then
        warn "Maximum 4 data slots (ids 3–6); ignoring extra --data files"
        break
    fi
done

# Save slots (ids 10+)
SAVE_ADDR=0x30000000
for i in $(seq 0 $((SAVES - 1))); do
    sid=$((10 + i))
    addr=$(printf "0x%08X" $SAVE_ADDR)
    DATA_SLOTS="$DATA_SLOTS,"'
            { "id": '"$sid"', "name": "Save '"$i"'", "required": false, "parameters": "0x85", "nonvolatile": true, "address": "'"$addr"'", "size_maximum": "'"$SAVE_SIZE"'", "filename": "'"${SNAME}_${i}.sav"'", "extensions": ["sav"] }'
    SAVE_ADDR=$((SAVE_ADDR + 0x40000))
done

cat > "$CORE_DIR/data.json" << ENDJSON
{
    "data": {
        "magic": "APF_VER_1",
        "data_slots": $DATA_SLOTS
        ]
    }
}
ENDJSON
    ok "Generated data.json ($SAVES save slots)"
fi

# ── Copy shared JSON configs (audio/video/input/interact/variants) ─
DIST_DIR=""
for try in "$SCRIPT_DIR/dist/sdk/core" "$SCRIPT_DIR/dist/sdk" "$RUNTIME/dist" "$SCRIPT_DIR/dist" ../openfpgaOS/dist; do
    if [[ -f "$try/audio.json" ]]; then
        DIST_DIR="$try"
        break
    fi
done

if [[ -n "$DIST_DIR" ]]; then
    for f in audio.json video.json input.json interact.json variants.json; do
        [[ -f "$DIST_DIR/$f" ]] && cp "$DIST_DIR/$f" "$CORE_DIR/"
    done
    ok "Copied shared JSON configs from $DIST_DIR"

    # Platform files
    if [[ -f "$PLATFORMS_DIR/${PLATFORM}.json" ]]; then
        ok "Platform JSON already exists, skipping"
    elif [[ -f "$DIST_DIR/platforms/${PLATFORM}.json" ]]; then
        cp "$DIST_DIR/platforms/${PLATFORM}.json" "$PLATFORMS_DIR/"
        [[ -f "$DIST_DIR/platforms/_images/${PLATFORM}.bin" ]] && \
            cp "$DIST_DIR/platforms/_images/${PLATFORM}.bin" "$PLATFORMS_DIR/_images/"
        ok "Copied platform files"
    else
        generate_platform_json "$PLATFORMS_DIR/${PLATFORM}.json"
    fi
else
    warn "dist/sdk/core/ not found — audio/video/input/interact/variants JSONs not copied"

    # Generate platform JSON when no dist directory available
    if [[ ! -f "$PLATFORMS_DIR/${PLATFORM}.json" ]]; then
        generate_platform_json "$PLATFORMS_DIR/${PLATFORM}.json"
    fi
fi

# ── Sincronizar dist/sdk/ con los metadatos de la nueva app ──────
DIST_SDK_CORE_JSON="$SCRIPT_DIR/dist/sdk/core/core.json"
if [[ -f "$DIST_SDK_CORE_JSON" ]]; then
    python3 -c "
import json, sys
path, platform, short, author, desc, ver, date = sys.argv[1:]
try:
    with open(path) as f:
        d = json.load(f)
    m = d['core']['metadata']
    m['platform_ids'] = [platform]
    m['shortname'] = short
    m['author'] = author
    m['description'] = desc
    m['version'] = ver
    m['date_release'] = date
    with open(path, 'w') as f:
        json.dump(d, f, indent=4)
except (KeyError, TypeError) as e:
    sys.exit(f'Error updating {path}: missing key {e}')
except Exception as e:
    sys.exit(f'Error updating {path}: {e}')
" "$DIST_SDK_CORE_JSON" "$PLATFORM" "$SHORT" "$AUTHOR" "$DESCRIPTION" "$VERSION" "$DATE"
    ok "Updated dist/sdk/core/core.json"
fi

DIST_SDK_PLATFORM="$SCRIPT_DIR/dist/sdk/platform"
mkdir -p "$DIST_SDK_PLATFORM/_images"
if [[ -f "$PLATFORMS_DIR/${PLATFORM}.json" ]]; then
    cp "$PLATFORMS_DIR/${PLATFORM}.json" "$DIST_SDK_PLATFORM/"
    ok "Updated dist/sdk/platform/${PLATFORM}.json"
fi
if [[ -f "$PLATFORMS_DIR/_images/${PLATFORM}.bin" ]]; then
    cp "$PLATFORMS_DIR/_images/${PLATFORM}.bin" "$DIST_SDK_PLATFORM/_images/"
    ok "Updated dist/sdk/platform/_images/${PLATFORM}.bin"
fi

# ── Actualizar PLATFORM y CORE_ID en el Makefile raíz si ya existe ─
ROOT_MK_EXISTING="$SCRIPT_DIR/Makefile"
if [[ -f "$ROOT_MK_EXISTING" ]]; then
    python3 -c "
import re, sys
path, platform, core_id = sys.argv[1:]
with open(path) as f:
    content = f.read()
content = re.sub(r'^PLATFORM(\s*=\s*).*', lambda m: 'PLATFORM' + m.group(1) + platform, content, flags=re.MULTILINE)
content = re.sub(r'^CORE_ID(\s*=\s*).*', lambda m: 'CORE_ID' + m.group(1) + core_id, content, flags=re.MULTILINE)
with open(path, 'w') as f:
    f.write(content)
" "$ROOT_MK_EXISTING" "$PLATFORM" "$CORE_ID"
    ok "Updated Makefile PLATFORM=$PLATFORM and CORE_ID=$CORE_ID"
fi

# ── Copy runtime files ────────────────────────────────────────────
if [[ -f "$BITSTREAM" ]]; then
    cp "$BITSTREAM" "$CORE_DIR/bitstream.rbf_r"
    ok "Copied bitstream.rbf_r"
fi

if [[ -f "$LOADER" ]]; then
    cp "$LOADER" "$CORE_DIR/loader.bin"
    ok "Copied loader.bin"
fi

if [[ -f "$OS_BIN" ]]; then
    cp "$OS_BIN" "$ASSETS_COMMON/os.bin"
    ok "Copied os.bin"
fi

cp "$ELF" "$ASSETS_COMMON/$ELF_NAME"
ok "Copied $ELF_NAME"

for df in "${DATA_FILES[@]}"; do
    cp "$df" "$ASSETS_COMMON/$(basename "$df")"
    ok "Copied $(basename "$df")"
done

# ── Icon ──────────────────────────────────────────────────────────
if [[ -n "$ICON" && -f "$ICON" ]]; then
    cp "$ICON" "$CORE_DIR/icon.bin"
    ok "Copied icon.bin"
fi

# ── Instance JSON ─────────────────────────────────────────────────
INSTANCE_JSON="$APP_DIR/${SNAME}.json"
if [[ ! -f "$INSTANCE_JSON" ]]; then
    DATA_SLOT_ENTRIES='[
            { "id": 1, "filename": "os.bin" },
            { "id": 2, "filename": "'"$ELF_NAME"'" }'
    islot=3
    for df in "${DATA_FILES[@]}"; do
        DATA_SLOT_ENTRIES="$DATA_SLOT_ENTRIES"', { "id": '"$islot"', "filename": "'"$(basename "$df")"'" }'
        islot=$((islot + 1))
        [[ $islot -gt 6 ]] && break
    done
    cat > "$INSTANCE_JSON" << JSON
{
    "instance": {
        "magic": "APF_VER_1",
        "variant_select": { "id": 666, "select": false },
        "data_slots": $DATA_SLOT_ENTRIES
        ],
        "display_modes": []
    }
}
JSON
    ok "src/$SNAME/${SNAME}.json"
fi

# Deploy instance JSON to Assets/<platform>/<CORE_ID>/
cp "$INSTANCE_JSON" "$ASSETS_INSTANCES/${SNAME}.json"
ok "Copied ${SNAME}.json to Assets/$PLATFORM/$CORE_ID/"

# ── Generate package_app.sh if not present ───────────────────────
PKG_SCRIPT="$SCRIPT_DIR/package_app.sh"
if [[ ! -f "$PKG_SCRIPT" ]]; then
    cat > "$PKG_SCRIPT" << 'PKGSCRIPT'
#!/bin/bash
#
# openfpgaOS SDK — App Packager
#
# Usage:
#   ./package_app.sh                 Package the default app (first app found in src/)
#   ./package_app.sh myapp           Package src/myapp/
#   APP=myapp ./package_app.sh       Same, via environment variable
#
set -e

GREEN='\033[92m'
CYAN='\033[96m'
YELLOW='\033[93m'
RED='\033[91m'
RESET='\033[0m'

SDK_DIR="$(cd "$(dirname "$0")" && pwd)"

# ── Resolver APP: argumento > variable de entorno > primera app en src/ ──
APP_NAME="${1:-${APP:-}}"

if [ -z "$APP_NAME" ]; then
    for d in "$SDK_DIR/src"/*/; do
        name=$(basename "$d")
        case "$name" in apps|sdk|tools) continue ;; esac
        if [ -f "$d/Makefile" ]; then
            APP_NAME="$name"
            break
        fi
    done
    [ -z "$APP_NAME" ] && {
        echo -e "${RED}Error: no se encontró ninguna app en src/. Usa: $0 <app_name>${RESET}"
        exit 1
    }
fi

BUILD="$SDK_DIR/build/sdk"
RELEASES="$SDK_DIR/releases"
RUNTIME="$SDK_DIR/runtime"

echo -e "${CYAN}=== App Packager (APP=$APP_NAME) ===${RESET}"

# ── Verificar que existe src/<app>/ ───────────────────────────────
if [ ! -d "$SDK_DIR/src/$APP_NAME" ]; then
    echo -e "${RED}Error: no existe src/$APP_NAME/${RESET}"
    exit 1
fi

# ── Leer CORE_ID y PLATFORM desde dist/sdk/core/core.json ────────
DIST_CORE_JSON="$SDK_DIR/dist/sdk/core/core.json"
[ -f "$DIST_CORE_JSON" ] || {
    echo -e "${RED}Error: $DIST_CORE_JSON no encontrado.${RESET}"
    exit 1
}

_CORE_META=$(python3 -c "
import json, sys
with open('$DIST_CORE_JSON') as f:
    d = json.load(f)
m = d['core']['metadata']
ids = m.get('platform_ids', [])
print(m['author'])
print(m['shortname'])
print(ids[0] if ids else '')
" 2>/dev/null)

CORE_AUTHOR=$(echo "$_CORE_META"   | sed -n '1p')
CORE_SHORTNAME=$(echo "$_CORE_META" | sed -n '2p')
PLATFORM=$(echo "$_CORE_META"      | sed -n '3p')

CORE_ID="${CORE_AUTHOR}.${CORE_SHORTNAME}"
[ -z "$CORE_AUTHOR" ] || [ -z "$CORE_SHORTNAME" ] || [ -z "$PLATFORM" ] && {
    echo -e "${RED}Error: no se pueden leer metadatos del core desde $DIST_CORE_JSON.${RESET}"
    exit 1
}

# ── Rutas de release ──────────────────────────────────────────────
REL_CORE="$BUILD/Cores/$CORE_ID"
REL_ASSETS="$BUILD/Assets/$PLATFORM/common"
REL_INSTANCE="$BUILD/Assets/$PLATFORM/$CORE_ID"
REL_PLATFORM_DIR="$BUILD/Platforms"

# ── Build app ─────────────────────────────────────────────────────
echo "  Building $APP_NAME..."
make -C "$SDK_DIR/src/$APP_NAME" SDK_DIR="$SDK_DIR/src/sdk"
[ -f "$SDK_DIR/src/$APP_NAME/app.elf" ] && \
    mv "$SDK_DIR/src/$APP_NAME/app.elf" "$SDK_DIR/src/$APP_NAME/$APP_NAME.elf" 2>/dev/null || true

# ── Crear estructura de release ───────────────────────────────────
echo "  Creating release structure..."
mkdir -p "$REL_CORE" "$REL_ASSETS" "$REL_INSTANCE" "$REL_PLATFORM_DIR/_images"

# Archivos de runtime
[ -f "$RUNTIME/bitstream.rbf_r" ] && cp "$RUNTIME/bitstream.rbf_r" "$REL_CORE/"
[ -f "$RUNTIME/loader.bin" ]      && cp "$RUNTIME/loader.bin"      "$REL_CORE/"
[ -f "$RUNTIME/os.bin" ]          && cp "$RUNTIME/os.bin"          "$REL_ASSETS/"

# Archivos de configuración del core desde dist/sdk/core/
[ -d "$SDK_DIR/dist/sdk/core" ] && \
    find "$SDK_DIR/dist/sdk/core" -maxdepth 1 \( -name "*.json" -o -name "*.bin" \) \
        -exec cp {} "$REL_CORE/" \; 2>/dev/null || true

# Archivos de plataforma desde dist/sdk/platform/ (solo el archivo de la plataforma actual)
[ -f "$SDK_DIR/dist/sdk/platform/${PLATFORM}.json" ] && \
    cp "$SDK_DIR/dist/sdk/platform/${PLATFORM}.json" "$REL_PLATFORM_DIR/" 2>/dev/null || true
[ -f "$SDK_DIR/dist/sdk/platform/_images/${PLATFORM}.bin" ] && \
    cp "$SDK_DIR/dist/sdk/platform/_images/${PLATFORM}.bin" "$REL_PLATFORM_DIR/_images/" 2>/dev/null || true

# ELF y datos de la app
cp "$SDK_DIR/src/$APP_NAME/$APP_NAME.elf" "$REL_ASSETS/"
find "$SDK_DIR/src/$APP_NAME" -maxdepth 1 \
    \( -name "*.mid" -o -name "*.wav" -o -name "*.dat" -o -name "*.png" \) \
    -exec cp {} "$REL_ASSETS/" \; 2>/dev/null || true

# JSON de instancia (si existe)
[ -f "$SDK_DIR/src/$APP_NAME/$APP_NAME.json" ] && \
    cp "$SDK_DIR/src/$APP_NAME/$APP_NAME.json" "$REL_INSTANCE/" || true

# ── Verificar build ───────────────────────────────────────────────
if [ ! -d "$BUILD/Cores" ]; then
    echo -e "${RED}Error: build/sdk/ no encontrado tras crear release.${RESET}"
    exit 1
fi

# ── Leer metadatos del core.json ──────────────────────────────────
CORE_JSON="$REL_CORE/core.json"
[ -f "$CORE_JSON" ] || {
    echo -e "${RED}Error: $CORE_JSON no encontrado.${RESET}"
    exit 1
}

GAME_NAME=$(python3 -c "
import json
with open('$CORE_JSON') as f:
    d = json.load(f)
print(d['core']['metadata']['description'])
" 2>/dev/null)
[ -z "$GAME_NAME" ] && {
    echo -e "${YELLOW}Warning: no se pudo leer description, usando '$APP_NAME'${RESET}"
    GAME_NAME="$APP_NAME"
}

CORE_VERSION=$(python3 -c "
import json
with open('$CORE_JSON') as f:
    d = json.load(f)
print(d['core']['metadata']['version'])
" 2>/dev/null)
[ -z "$CORE_VERSION" ] && {
    echo -e "${YELLOW}Warning: no se pudo leer version, usando '1.0.0'${RESET}"
    CORE_VERSION="1.0.0"
}

OUTPUT_ZIP="$RELEASES/${APP_NAME}-v${CORE_VERSION}.zip"
echo "  Version : $CORE_VERSION"
echo "  Output  : $OUTPUT_ZIP"
echo

# ── Verificar ELF ─────────────────────────────────────────────────
if [ ! -f "$REL_ASSETS/${APP_NAME}.elf" ]; then
    echo -e "${RED}Error: ${APP_NAME}.elf no encontrado en $REL_ASSETS/${RESET}"
    exit 1
fi

# ── Generar INSTALL.txt ───────────────────────────────────────────
cat > "$BUILD/INSTALL.txt" << EOF
$GAME_NAME
$(printf '=%.0s' $(seq 1 ${#GAME_NAME}))
Version: $CORE_VERSION

Installation:
1. Extract this ZIP to your Analogue Pocket SD card root
2. Merge with existing folders if prompted
3. The app will appear in the Pocket menu

Save files are created automatically on first use.
EOF

# ── Crear ZIP ─────────────────────────────────────────────────────
mkdir -p "$RELEASES"
rm -f "$OUTPUT_ZIP" 2>/dev/null || true

cd "$BUILD"
zip -r "$OUTPUT_ZIP" \
    Cores/ Assets/ Platforms/ INSTALL.txt \
    -x "*.DS_Store" "Thumbs.db" 2>/dev/null
cd "$SDK_DIR"

echo -e "${GREEN}Package created: $OUTPUT_ZIP${RESET}"
echo "  Size: $(du -h "$OUTPUT_ZIP" | cut -f1)"
PKGSCRIPT
    chmod +x "$PKG_SCRIPT"
    ok "Generated package_app.sh"
fi

# ── Generate root Makefile if not present ────────────────────────
ROOT_MK="$SCRIPT_DIR/Makefile"
if [[ ! -f "$ROOT_MK" ]]; then
    cat > "$ROOT_MK" << ROOTMK
# openfpgaOS SDK Makefile — generated by create_app.sh
#
# Usage:
#   make                    Build app and create release/
#   make APP=other_app      Build a different app
#   make deploy             Copy release/ to Pocket SD card
#   make clean              Remove all build artifacts
#   make package            Package into a ZIP release

# ── App (override: make APP=other) ───────────────────────────────
APP ?= $SNAME

# ── Paths ────────────────────────────────────────────────────────
CORE_ID      = $CORE_ID
PLATFORM     = $PLATFORM
RELEASE      = build/sdk
REL_CORE     = \$(RELEASE)/Cores/\$(CORE_ID)
REL_ASSETS   = \$(RELEASE)/Assets/\$(PLATFORM)/common
REL_INSTANCE = \$(RELEASE)/Assets/\$(PLATFORM)/\$(CORE_ID)
REL_PLATFORM = \$(RELEASE)/Platforms
RUNTIME      = runtime

# ── Default target ───────────────────────────────────────────────
all: app release

# ── Build app ────────────────────────────────────────────────────
app:
	@echo "Building \$(APP)..."
	\$(MAKE) -C src/\$(APP) SDK_DIR=\$(CURDIR)/src/sdk
	@[ -f src/\$(APP)/app.elf ] && mv src/\$(APP)/app.elf src/\$(APP)/\$(APP).elf 2>/dev/null || true

# ── Create release/ directory ────────────────────────────────────
release: app
	@echo "Creating release/..."
	@mkdir -p \$(REL_CORE) \$(REL_ASSETS) \$(REL_INSTANCE) \$(REL_PLATFORM)/_images
	@cp \$(RUNTIME)/bitstream.rbf_r \$(REL_CORE)/
	@cp \$(RUNTIME)/loader.bin \$(REL_CORE)/
	@[ -d dist/sdk/core ] && cp dist/sdk/core/*.json dist/sdk/core/*.bin \$(REL_CORE)/ 2>/dev/null || true
	@[ -f dist/sdk/platform/\$(PLATFORM).json ] && cp dist/sdk/platform/\$(PLATFORM).json \$(REL_PLATFORM)/ 2>/dev/null || true
	@[ -f dist/sdk/platform/_images/\$(PLATFORM).bin ] && cp dist/sdk/platform/_images/\$(PLATFORM).bin \$(REL_PLATFORM)/_images/ 2>/dev/null || true
	@cp \$(RUNTIME)/os.bin \$(REL_ASSETS)/
	@cp src/\$(APP)/\$(APP).elf \$(REL_ASSETS)/
	@find src/\$(APP) -maxdepth 1 \( -name "*.mid" -o -name "*.wav" -o -name "*.dat" -o -name "*.png" \) \
		-exec cp {} "\$(REL_ASSETS)/" \; 2>/dev/null || true
	@[ -f src/\$(APP)/\$(APP).json ] && cp src/\$(APP)/\$(APP).json \$(REL_INSTANCE)/ || true
	@echo "Release ready: \$(RELEASE)/"

# ── Deploy to SD card ────────────────────────────────────────────
deploy: release
	@./scripts/deploy.sh

# ── Clean ────────────────────────────────────────────────────────
clean:
	\$(MAKE) -C src/\$(APP) clean
	rm -rf build releases

# ── Core creation ────────────────────────────────────────────────
core:
	./create_app.sh

# ── Package into ZIP ─────────────────────────────────────────────
package:
	./package_app.sh \$(APP)

.PHONY: all app release deploy clean core package
ROOTMK
    ok "Generated Makefile"
fi

# ══════════════════════════════════════════════════════════════════
# Final summary
# ══════════════════════════════════════════════════════════════════
header "Done"

echo
ok "App created successfully!"
echo
echo "  App source : src/$SNAME/"
echo "  app.conf   : src/$SNAME/app.conf"
echo "  Core output: $OUTPUT/"
echo "  Makefile   : Makefile (root)"
echo "  Packager   : package_app.sh"
echo
echo "Next steps:"
echo "  1. Edit src/$SNAME/main.c with your application logic"
echo "  2. make -C src/$SNAME          # recompile"
echo "  3. make deploy                 # deploy to SD card"
echo "  4. ./package_app.sh $SNAME     # package into a ZIP release"
echo
