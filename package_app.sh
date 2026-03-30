#!/bin/bash
#
# openfpgaOS SDK — App Packager
#
# Usage:
#   ./package_app.sh                 Package the default app (APP ?= en Makefile)
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

# ── Resolver APP: argumento > variable de entorno > default del Makefile ──
APP_NAME="${1:-${APP:-}}"

if [ -z "$APP_NAME" ]; then
    APP_NAME=$(grep -E '^APP\s*\?=' "$SDK_DIR/Makefile" 2>/dev/null \
        | head -1 | sed 's/.*=\s*//' | tr -d '[:space:]')
    [ -z "$APP_NAME" ] && {
        echo -e "${RED}Error: no se encuentra APP ?= en el Makefile.${RESET}"
        exit 1
    }
fi

BUILD="$SDK_DIR/build/sdk"
RELEASES="$SDK_DIR/releases"

echo -e "${CYAN}=== App Packager (APP=$APP_NAME) ===${RESET}"

# ── Verificar que existe src/<app>/ ───────────────────────────────
if [ ! -d "$SDK_DIR/src/$APP_NAME" ]; then
    echo -e "${RED}Error: no existe src/$APP_NAME/${RESET}"
    exit 1
fi

# ── Leer metadatos de app.conf ────────────────────────────────────
APP_CONF="$SDK_DIR/src/$APP_NAME/app.conf"
read_conf() { grep -E "^$1=" "$APP_CONF" 2>/dev/null | head -1 | sed "s/$1=//"; }
PLATFORM=""
AUTHOR=""
SHORT=""
if [ -f "$APP_CONF" ]; then
    PLATFORM=$(read_conf PLATFORM)
    AUTHOR=$(read_conf AUTHOR)
    SHORT=$(read_conf SHORT)
fi
[ -z "$PLATFORM" ] && PLATFORM="raytracertnw"
[ -z "$SHORT" ] && SHORT="raytracerTNW"
[ -z "$AUTHOR" ] && AUTHOR="RndMnkIII"
CORE_ID="${AUTHOR}.${SHORT}"

# ── Build ─────────────────────────────────────────────────────────
echo "  Building release..."
if grep -qE '^release[[:space:]]*:' "$SDK_DIR/Makefile" 2>/dev/null; then
    make -C "$SDK_DIR" release APP="$APP_NAME"
else
    echo -e "${YELLOW}  No 'release' target in Makefile — building app and packaging manually.${RESET}"
    make -C "$SDK_DIR" APP="$APP_NAME" 2>/dev/null || make -C "$SDK_DIR"

    RUNTIME="$SDK_DIR/runtime"
    REL_CORE_DIR="$BUILD/Cores/$CORE_ID"
    REL_ASSETS_DIR="$BUILD/Assets/$PLATFORM/common"
    REL_INSTANCE_DIR="$BUILD/Assets/$PLATFORM/$CORE_ID"
    REL_PLATFORM_DIR="$BUILD/Platforms"

    mkdir -p "$REL_CORE_DIR" "$REL_ASSETS_DIR" "$REL_INSTANCE_DIR" "$REL_PLATFORM_DIR/_images"

    # Copy runtime files
    [ -f "$RUNTIME/bitstream.rbf_r" ] && cp "$RUNTIME/bitstream.rbf_r" "$REL_CORE_DIR/"
    [ -f "$RUNTIME/loader.bin" ]      && cp "$RUNTIME/loader.bin"      "$REL_CORE_DIR/"

    # Copy core metadata (new-style dist first, then legacy dist/sdk)
    DIST_CORE_SRC="$SDK_DIR/dist/$SHORT/Cores/$CORE_ID"
    DIST_CORE_LEGACY="$SDK_DIR/dist/sdk/core"
    if [ -d "$DIST_CORE_SRC" ]; then
        cp "$DIST_CORE_SRC"/*.json "$REL_CORE_DIR/" 2>/dev/null || true
        cp "$DIST_CORE_SRC"/*.bin  "$REL_CORE_DIR/" 2>/dev/null || true
    elif [ -d "$DIST_CORE_LEGACY" ]; then
        cp "$DIST_CORE_LEGACY"/*.json "$REL_CORE_DIR/" 2>/dev/null || true
        cp "$DIST_CORE_LEGACY"/*.bin  "$REL_CORE_DIR/" 2>/dev/null || true
    fi

    # Copy platform metadata
    DIST_PLAT_SRC="$SDK_DIR/dist/$SHORT/Platforms"
    DIST_PLAT_LEGACY="$SDK_DIR/dist/sdk/platform"
    if [ -d "$DIST_PLAT_SRC" ]; then
        cp "$DIST_PLAT_SRC"/*.json "$REL_PLATFORM_DIR/" 2>/dev/null || true
        [ -d "$DIST_PLAT_SRC/_images" ] && \
            cp "$DIST_PLAT_SRC/_images"/*.bin "$REL_PLATFORM_DIR/_images/" 2>/dev/null || true
    elif [ -d "$DIST_PLAT_LEGACY" ]; then
        cp "$DIST_PLAT_LEGACY"/*.json "$REL_PLATFORM_DIR/" 2>/dev/null || true
        [ -d "$DIST_PLAT_LEGACY/_images" ] && \
            cp "$DIST_PLAT_LEGACY/_images"/*.bin "$REL_PLATFORM_DIR/_images/" 2>/dev/null || true
    fi

    # Copy OS binary
    [ -f "$RUNTIME/os.bin" ] && cp "$RUNTIME/os.bin" "$REL_ASSETS_DIR/"

    # Copy ELF (rename app.elf -> $APP_NAME.elf if needed)
    ELF_SRC="$SDK_DIR/src/$APP_NAME/${APP_NAME}.elf"
    if [ ! -f "$ELF_SRC" ] && [ -f "$SDK_DIR/src/$APP_NAME/app.elf" ]; then
        cp "$SDK_DIR/src/$APP_NAME/app.elf" "$ELF_SRC"
    fi
    [ -f "$ELF_SRC" ] && cp "$ELF_SRC" "$REL_ASSETS_DIR/"

    # Copy data files
    find "$SDK_DIR/src/$APP_NAME" -maxdepth 1 \
        \( -name "*.mid" -o -name "*.wav" -o -name "*.dat" -o -name "*.png" \) \
        -exec cp {} "$REL_ASSETS_DIR/" \; 2>/dev/null || true

    # Copy instance JSON
    [ -f "$SDK_DIR/src/$APP_NAME/${APP_NAME}.json" ] && \
        cp "$SDK_DIR/src/$APP_NAME/${APP_NAME}.json" "$REL_INSTANCE_DIR/" || true
fi

# ── Verificar build ───────────────────────────────────────────────
if [ ! -d "$BUILD/Cores" ]; then
    echo -e "${RED}Error: build/sdk/ no encontrado tras make release.${RESET}"
    exit 1
fi

# ── Leer metadatos del core.json ──────────────────────────────────
CORE_NAME=$(ls "$BUILD/Cores/" 2>/dev/null | head -1)
[ -z "$CORE_NAME" ] && {
    echo -e "${RED}Error: no se encuentra ningún core en build/sdk/Cores/.${RESET}"
    exit 1
}

CORE_JSON="$BUILD/Cores/$CORE_NAME/core.json"
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
REL_ASSETS="$BUILD/Assets/$PLATFORM/common"
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
