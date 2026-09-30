#!/bin/bash
# Regenerates Resources/GuitarHUD.icns from make-icon.swift.
set -euo pipefail
cd "$(dirname "$0")"
TMP="$(mktemp -d)"
swiftc -O make-icon.swift -o "$TMP/make-icon"
"$TMP/make-icon" "$TMP/GuitarHUD.iconset"
iconutil -c icns "$TMP/GuitarHUD.iconset" -o ../Resources/GuitarHUD.icns
rm -rf "$TMP"
echo "==> ../Resources/GuitarHUD.icns ($(du -h ../Resources/GuitarHUD.icns | cut -f1))"
