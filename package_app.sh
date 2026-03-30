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
