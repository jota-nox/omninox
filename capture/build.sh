#!/bin/bash
# Build do OmniNox Capture v2 (Swift nativo, sem projeto Xcode)
set -euo pipefail
cd "$(dirname "$0")"

APP="OmniNox Capture"
BUILD=build

echo "· compilando Capture.swift"
swiftc -O -parse-as-library Capture.swift -o "$BUILD/capture-bin" 2>&1 | head -40 || true
test -f "$BUILD/capture-bin" || { mkdir -p "$BUILD"; swiftc -O -parse-as-library Capture.swift -o "$BUILD/capture-bin"; }

echo "· montando bundle"
rm -rf "$BUILD/$APP.app"
mkdir -p "$BUILD/$APP.app/Contents/MacOS" "$BUILD/$APP.app/Contents/Resources"
cp "$BUILD/capture-bin" "$BUILD/$APP.app/Contents/MacOS/$APP"
cp Info.plist "$BUILD/$APP.app/Contents/"
for f in assets/iconTemplate.png assets/iconTemplate@2x.png assets/icon.icns; do
  [ -f "$f" ] && cp "$f" "$BUILD/$APP.app/Contents/Resources/"
done

echo "· codesign ad-hoc"
codesign --force -s - "$BUILD/$APP.app"

echo "OK → $BUILD/$APP.app"
