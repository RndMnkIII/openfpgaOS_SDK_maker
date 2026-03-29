#!/usr/bin/env bash
# ── create_app.sh ─────────────────────────────────────────────────
# Crea una app standalone completa para openfpgaOS SDK:
#   - Estructura src/<app>/ con Makefile y fuentes de ejemplo
#   - Opcionalmente una librería estática src/<app>/<lib>/
#   - Makefile raíz apuntando a la app
#   - Script package_app.sh listo para usar
#
# Uso:
#   ./create_app.sh <nombre_app> [--lib <nombre_lib>] \
#                                [--core-id <id>] [--platform <nombre>]
#
# Si --core-id o --platform no se proporcionan, se preguntará
# de forma interactiva (con valores por defecto para compatibilidad).
#
# ──────────────────────────────────────────────────────────────────
set -e

# ── Colores ───────────────────────────────────────────────────────
RED='\033[0;31m'
GRN='\033[0;32m'
YLW='\033[0;33m'
BLU='\033[0;34m'
CYN='\033[0;36m'
RST='\033[0m'

info()    { echo -e "${BLU}[info]${RST}  $*"; }
ok()      { echo -e "${GRN}[ok]${RST}    $*"; }
warn()    { echo -e "${YLW}[warn]${RST}  $*"; }
error()   { echo -e "${RED}[error]${RST} $*"; exit 1; }
ask()     { echo -e "${CYN}[?]${RST}     $*"; }
header()  { echo -e "\n${CYN}══ $* ══${RST}"; }

# ── Argumentos ────────────────────────────────────────────────────
APP_NAME=""
LIB_NAME=""
CORE_ID=""
PLATFORM=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --lib)
            [[ -n "$2" ]] || error "--lib requiere un nombre"
            LIB_NAME="$2"
            shift 2
            ;;
        --core-id)
            [[ -n "$2" ]] || error "--core-id requiere un valor"
            CORE_ID="$2"
            shift 2
            ;;
        --platform)
            [[ -n "$2" ]] || error "--platform requiere un valor"
            PLATFORM="$2"
            shift 2
            ;;
        -*)
            error "Opción desconocida: $1"
            ;;
        *)
            [[ -z "$APP_NAME" ]] || error "Nombre de app duplicado: $1"
            APP_NAME="$1"
            shift
            ;;
    esac
done

[[ -n "$APP_NAME" ]] || error "Uso: $0 <nombre_app> [--lib <nombre_lib>] [--core-id <id>] [--platform <nombre>]"

[[ "$APP_NAME" =~ ^[a-zA-Z0-9_]+$ ]] || \
    error "El nombre solo puede contener letras, números y guiones bajos"
[[ -n "$LIB_NAME" ]] && { [[ "$LIB_NAME" =~ ^[a-zA-Z0-9_]+$ ]] || \
    error "El nombre de la lib solo puede contener letras, números y guiones bajos"; }

# ── Rutas base ────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$SCRIPT_DIR/src/$APP_NAME"
ROOT_MK="$SCRIPT_DIR/Makefile"
PKG_SH="$SCRIPT_DIR/package_app.sh"

# ── Localizar SDK ─────────────────────────────────────────────────
SDK_ABS="$(find "$SCRIPT_DIR/src" -maxdepth 2 -name "sdk.mk" 2>/dev/null \
    | head -1 | xargs dirname 2>/dev/null)"
[[ -n "$SDK_ABS" ]] || error "No se encuentra sdk.mk bajo $SCRIPT_DIR/src/. ¿Estás en la raíz del proyecto?"

SDK_REL="$(python3 -c "import os; print(os.path.relpath('$SDK_ABS', '$APP_DIR'))")"

# ── Preguntar librería si no se pasó por argumento ────────────────
header "Configuración"

if [[ -z "$LIB_NAME" ]]; then
    ask "¿La app incluye una librería estática propia? [s/N]"
    read -r ans
    if [[ "$ans" =~ ^[sS]$ ]]; then
        ask "Nombre de la librería:"
        read -r LIB_NAME
        [[ "$LIB_NAME" =~ ^[a-zA-Z0-9_]+$ ]] || \
            error "El nombre de la lib solo puede contener letras, números y guiones bajos"
    fi
fi

LIB_SDK_REL=""
[[ -n "$LIB_NAME" ]] && \
    LIB_SDK_REL="$(python3 -c "import os; print(os.path.relpath('$SDK_ABS', '$APP_DIR/$LIB_NAME'))")"

# ── Preguntar Core ID si no se pasó por argumento ─────────────────
DEFAULT_CORE_ID="ThinkElastic.openfpgaOS"
if [[ -z "$CORE_ID" ]]; then
    ask "Core ID (p.e., $DEFAULT_CORE_ID): "
    read -r CORE_ID
    [[ -z "$CORE_ID" ]] && CORE_ID="$DEFAULT_CORE_ID"
fi

# ── Preguntar Platform si no se pasó por argumento ────────────────
DEFAULT_PLATFORM="openfpgaos"
if [[ -z "$PLATFORM" ]]; then
    ask "Platform name (p.e., $DEFAULT_PLATFORM): "
    read -r PLATFORM
    [[ -z "$PLATFORM" ]] && PLATFORM="$DEFAULT_PLATFORM"
fi

echo ""
info "App      : $APP_NAME"
info "Core ID  : $CORE_ID"
info "Platform : $PLATFORM"
info "SDK      : $(realpath --relative-to="$SCRIPT_DIR" "$SDK_ABS")"
[[ -n "$LIB_NAME" ]] && info "Lib      : $LIB_NAME"
info "Destino  : src/$APP_NAME/"

# ── Comprobar si app ya existe ────────────────────────────────────
[[ -d "$APP_DIR" ]] && error "Ya existe src/$APP_NAME/"

# ══════════════════════════════════════════════════════════════════
# 1. ESTRUCTURA DE LA APP
# ══════════════════════════════════════════════════════════════════
header "Creando src/$APP_NAME/"

mkdir -p "$APP_DIR"
[[ -n "$LIB_NAME" ]] && mkdir -p "$APP_DIR/$LIB_NAME/include" "$APP_DIR/$LIB_NAME/src"

# ── Makefile de la app ────────────────────────────────────────────
if [[ -n "$LIB_NAME" ]]; then
cat > "$APP_DIR/Makefile" << MAKEFILE
# src/$APP_NAME/Makefile

SDK_DIR = $SDK_REL

# ── Fuentes de la app ─────────────────────────────────────────────
SRCS     = utilidades.c
SRCS_CXX = main.cpp

# ── Librería estática ─────────────────────────────────────────────
LIB     = $LIB_NAME/lib${LIB_NAME}.a
LIB_INC = -I $LIB_NAME/include

include \$(SDK_DIR)/sdk.mk
AR = \$(CROSS)ar

ALL_CFLAGS   += \$(LIB_INC)
ALL_CXXFLAGS += \$(LIB_INC)

\$(LIB):
	\$(MAKE) -C $LIB_NAME SDK_DIR=\$(CURDIR)/$SDK_REL

app.elf: \$(OBJS) \$(LIB) \$(APP_LD)
	\$(LD) \$(ALL_LDFLAGS) -o \$@ \$(OBJS) \$(LIB) \$(LIBGCC)

\$(CRT_DIR)/start.o: \$(CRT_DIR)/start.S
	\$(AS) \$(ASFLAGS) -c -o \$@ \$<

all: \$(LIB) app.elf
	\$(SIZE) app.elf

clean: sdk-clean
	\$(MAKE) -C $LIB_NAME clean

.PHONY: all clean
MAKEFILE
else
cat > "$APP_DIR/Makefile" << MAKEFILE
# src/$APP_NAME/Makefile

SDK_DIR = $SDK_REL

# ── Fuentes de la app ─────────────────────────────────────────────
SRCS     = utilidades.c
SRCS_CXX = main.cpp

include \$(SDK_DIR)/sdk.mk

app.elf: \$(OBJS) \$(APP_LD)
	\$(LD) \$(ALL_LDFLAGS) -o \$@ \$(OBJS) \$(LIBGCC)

\$(CRT_DIR)/start.o: \$(CRT_DIR)/start.S
	\$(AS) \$(ASFLAGS) -c -o \$@ \$<

all: app.elf
	\$(SIZE) app.elf

clean: sdk-clean

.PHONY: all clean
MAKEFILE
fi
ok "src/$APP_NAME/Makefile"

# ── Makefile de la lib ────────────────────────────────────────────
if [[ -n "$LIB_NAME" ]]; then
cat > "$APP_DIR/$LIB_NAME/Makefile" << MAKEFILE
# src/$APP_NAME/$LIB_NAME/Makefile

SDK_DIR = $LIB_SDK_REL

SRCS     = src/modulo1.c src/modulo2.c
SRCS_CXX = src/modulo3.cpp
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
ok "src/$APP_NAME/$LIB_NAME/Makefile"
fi

# ── Fuentes de ejemplo — app ──────────────────────────────────────
cat > "$APP_DIR/main.cpp" << CPP
// src/$APP_NAME/main.cpp
#include <of.h>
$([ -n "$LIB_NAME" ] && echo "#include \"${LIB_NAME}.h\"")

int main(void) {
    of_video_clear(0x000000);

    // TODO: inicializa tu app aquí

    while (1) {
        of_input_t input = of_input_read();

        if (input.buttons & OF_BTN_MENU)
            break;

        // TODO: lógica principal

        of_video_flip();
    }

    return 0;
}
CPP
ok "src/$APP_NAME/main.cpp"

cat > "$APP_DIR/utilidades.c" << CC
// src/$APP_NAME/utilidades.c
#include "utilidades.h"

// TODO: implementa tus utilidades aquí
CC
ok "src/$APP_NAME/utilidades.c"

cat > "$APP_DIR/utilidades.h" << HH
// src/$APP_NAME/utilidades.h
#pragma once

// TODO: declara tus utilidades aquí
HH
ok "src/$APP_NAME/utilidades.h"

# ── Fuentes de ejemplo — lib ──────────────────────────────────────
if [[ -n "$LIB_NAME" ]]; then
cat > "$APP_DIR/$LIB_NAME/include/${LIB_NAME}.h" << HH
// src/$APP_NAME/$LIB_NAME/include/${LIB_NAME}.h
#pragma once

void ${LIB_NAME}_init(void);
void ${LIB_NAME}_update(void);
HH
ok "src/$APP_NAME/$LIB_NAME/include/${LIB_NAME}.h"

cat > "$APP_DIR/$LIB_NAME/src/modulo1.c" << CC
// src/$APP_NAME/$LIB_NAME/src/modulo1.c
#include "${LIB_NAME}.h"

void ${LIB_NAME}_init(void) {
    // TODO: inicialización
}
CC
ok "src/$APP_NAME/$LIB_NAME/src/modulo1.c"

cat > "$APP_DIR/$LIB_NAME/src/modulo2.c" << CC
// src/$APP_NAME/$LIB_NAME/src/modulo2.c
#include "${LIB_NAME}.h"

void ${LIB_NAME}_update(void) {
    // TODO: lógica de actualización
}
CC
ok "src/$APP_NAME/$LIB_NAME/src/modulo2.c"

cat > "$APP_DIR/$LIB_NAME/src/modulo3.cpp" << CPP
// src/$APP_NAME/$LIB_NAME/src/modulo3.cpp
#include "${LIB_NAME}.h"

// TODO: módulo C++ de $LIB_NAME
CPP
ok "src/$APP_NAME/$LIB_NAME/src/modulo3.cpp"
fi

# ── Instance JSON ─────────────────────────────────────────────────
cat > "$APP_DIR/${APP_NAME}.json" << JSON
{
    "instance": {
        "magic": "APF_VER_1",
        "variant_select": {
            "id": 666,
            "select": false
        },
        "data_slots": [
                        {
                "id": 1,
                "filename": "os.bin"
            },
            {
                "id": 2,
                "filename": "${APP_NAME}..elf"
            }
        ],
        "display_modes": []
    }
}

JSON
ok "src/$APP_NAME/${APP_NAME}.json"

# ══════════════════════════════════════════════════════════════════
# 2. MAKEFILE RAÍZ
# ══════════════════════════════════════════════════════════════════
header "Makefile raíz"

WRITE_MK=1
if [[ -f "$ROOT_MK" ]]; then
    ask "Ya existe un Makefile raíz. ¿Sobreescribir? [s/N]"
    read -r ans
    [[ "$ans" =~ ^[sS]$ ]] || WRITE_MK=0
fi

if [[ "$WRITE_MK" == "1" ]]; then
    [[ -f "$ROOT_MK" ]] && cp "$ROOT_MK" "$ROOT_MK.bak" && info "Backup guardado en Makefile.bak"
cat > "$ROOT_MK" << 'MAKEFILE'
# openfpgaOS SDK Makefile
#
# Usage:
#   make                    Build app, create release/
#   make APP=otra_app       Build a different app
#   make deploy             Copy release/ to Pocket SD card
#   make clean              Remove all build artifacts
#   make core               Build a standalone game core (interactive)
#   make package            Package game core into a ZIP
MAKEFILE

cat >> "$ROOT_MK" << MAKEFILE

# ── App (override: make APP=otra_app) ────────────────────────────
APP ?= $APP_NAME

# ── Identidad del core / plataforma ──────────────────────────────
CORE_ID  = $CORE_ID
PLATFORM = $PLATFORM

MAKEFILE

cat >> "$ROOT_MK" << 'MAKEFILE'
# ── Paths ────────────────────────────────────────────────────────
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
	./scripts/customize.sh

package:
	./scripts/package.sh

.PHONY: all app tools release deploy clean core package
MAKEFILE
    ok "Makefile"
else
    warn "Makefile raíz no modificado."
fi

# ══════════════════════════════════════════════════════════════════
# 3. PACKAGE_APP.SH
# ══════════════════════════════════════════════════════════════════
header "package_app.sh"

WRITE_PKG=1
if [[ -f "$PKG_SH" ]]; then
    ask "Ya existe package_app.sh. ¿Sobreescribir? [s/N]"
    read -r ans
    [[ "$ans" =~ ^[sS]$ ]] || WRITE_PKG=0
fi

if [[ "$WRITE_PKG" == "1" ]]; then
cat > "$PKG_SH" << 'PKGSH'
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

# ── Build ─────────────────────────────────────────────────────────
echo "  Building release..."
make -C "$SDK_DIR" release APP="$APP_NAME"

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
PLATFORM=$(grep -E '^PLATFORM\s*=' "$SDK_DIR/Makefile" 2>/dev/null \
    | head -1 | sed 's/^PLATFORM\s*=\s*//' | tr -d '[:space:]')
[ -z "$PLATFORM" ] && PLATFORM="openfpgaos"
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
PKGSH
    chmod +x "$PKG_SH"
    ok "package_app.sh"
else
    warn "package_app.sh no modificado."
fi

# ══════════════════════════════════════════════════════════════════
# RESUMEN FINAL
# ══════════════════════════════════════════════════════════════════
header "Resumen"

info "Archivos creados:"
find "$APP_DIR" | sed "s|$SCRIPT_DIR/||" | sort | while read -r line; do
    if [[ -d "$SCRIPT_DIR/$line" ]]; then
        echo -e "  ${BLU}${line}/${RST}"
    else
        echo "  $line"
    fi
done

echo ""
ok "Listo. Comandos disponibles:"
echo -e "  ${YLW}make${RST}                             # compila y empaqueta $APP_NAME"
echo -e "  ${YLW}make APP=$APP_NAME${RST}         # ídem explícito"
echo -e "  ${YLW}make -C src/$APP_NAME${RST}      # compila solo la app"
echo -e "  ${YLW}./package_app.sh${RST}                 # genera el ZIP distribuible"
echo -e "  ${YLW}./package_app.sh $APP_NAME${RST} # ídem explícito"
echo ""
