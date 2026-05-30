#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CAPTURE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$SCRIPT_DIR/.build"
DIST_DIR="$SCRIPT_DIR/dist"
CAPTURE_APP="$CAPTURE_ROOT/dist/mac-arm64/OmniNox Capture.app"
OBSIDIAN_APP="/Applications/Obsidian.app"

if [ ! -d "$CAPTURE_APP" ]; then
  echo "Erro: OmniNox Capture.app não encontrado em $CAPTURE_APP"
  echo "Rode 'npm install && npm run build' em $CAPTURE_ROOT primeiro."
  exit 1
fi

echo "==> Limpando builds anteriores..."
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR/payload/Applications" "$DIST_DIR"

echo "==> Copiando OmniNox Capture..."
cp -R "$CAPTURE_APP" "$BUILD_DIR/payload/Applications/"

if [ -d "$OBSIDIAN_APP" ]; then
  echo "==> Copiando Obsidian..."
  cp -R "$OBSIDIAN_APP" "$BUILD_DIR/payload/Applications/"
else
  echo "==> Obsidian.app não encontrado em /Applications — pulando (será instalado via Homebrew)."
fi

echo "==> Buildando componente PKG..."
pkgbuild \
  --root "$BUILD_DIR/payload" \
  --scripts "$SCRIPT_DIR/scripts" \
  --identifier "com.omninox.installer" \
  --version "1.0.0" \
  --install-location "/" \
  "$BUILD_DIR/omninox.pkg"

echo "==> Criando instalador final..."
productbuild \
  --distribution "$SCRIPT_DIR/Distribution.xml" \
  --package-path "$BUILD_DIR" \
  --resources "$SCRIPT_DIR/resources" \
  "$DIST_DIR/OmniNox Install.pkg"

echo ""
echo "Pronto!"
du -sh "$DIST_DIR/OmniNox Install.pkg"
