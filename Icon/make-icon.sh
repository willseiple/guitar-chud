#!/bin/bash
# Regenerates Resources/GuitarCHUD.icns from make-icon.swift.
set -euo pipefail
cd "$(dirname "$0")"
TMP="$(mktemp -d)"
swiftc -O make-icon.swift -o "$TMP/make-icon"
"$TMP/make-icon" "$TMP/GuitarCHUD.iconset"
iconutil -c icns "$TMP/GuitarCHUD.iconset" -o ../Resources/GuitarCHUD.icns
rm -rf "$TMP"
echo "==> ../Resources/GuitarCHUD.icns ($(du -h ../Resources/GuitarCHUD.icns | cut -f1))"
