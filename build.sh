#!/bin/bash
# Builds GuitarCHUD.app from source. Re-run this after editing anything.
set -euo pipefail

cd "$(dirname "$0")"
APP="GuitarCHUD.app"

#   ./build.sh                 build here, this Mac's architecture
#   ./build.sh /Applications   install elsewhere
#   ./build.sh --share         universal build + a zip you can send someone
UNIVERSAL=0
SHARE=0
DEST="$PWD"
for arg in "$@"; do
  case "$arg" in
    --universal) UNIVERSAL=1 ;;
    --share)     UNIVERSAL=1; SHARE=1; DEST="$PWD/dist" ;;
    -*)          echo "unknown option: $arg" >&2; exit 1 ;;
    *)           DEST="$arg" ;;
  esac
done
mkdir -p "$DEST"
OUT="$DEST/$APP"

# Replacing a bundle while it's running confuses macOS, so stand it down first
# and put it back up afterwards if it was up.
WAS_RUNNING=0
if [ "$SHARE" = "0" ] && pgrep -f "$APP/Contents/MacOS/GuitarCHUD" >/dev/null 2>&1; then
  WAS_RUNNING=1
  echo "==> Quitting the running copy"
  osascript -e 'tell application id "com.willseiple.guitarhud" to quit' 2>/dev/null \
    || pkill -f "$APP/Contents/MacOS/GuitarCHUD" 2>/dev/null
  sleep 1
fi

echo "==> Building $OUT"
rm -rf "$OUT"
mkdir -p "$OUT/Contents/MacOS" "$OUT/Contents/Resources"

# The bundle id keeps the old guitarhud name on purpose: macOS ties the Spotify
# permission to it, so existing installs don't have to grant it again.
cat > "$OUT/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>GuitarCHUD</string>
  <key>CFBundleDisplayName</key><string>GuitarCHUD</string>
  <key>CFBundleExecutable</key><string>GuitarCHUD</string>
  <key>CFBundleIdentifier</key><string>com.willseiple.guitarhud</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleIconFile</key><string>GuitarCHUD</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSAppleEventsUsageDescription</key>
  <string>GuitarCHUD reads the song Spotify is playing so it can pull up the matching guitar chords.</string>
</dict>
</plist>
PLIST

SRC=(Sources/Spotify.swift Sources/UltimateGuitar.swift Sources/main.swift)
BIN="$OUT/Contents/MacOS/GuitarCHUD"

if [ "$UNIVERSAL" = "1" ]; then
  # Intel Macs can't run an arm64-only build, so ship both slices.
  echo "==> Compiling arm64 + x86_64"
  TMP="$(mktemp -d)"
  swiftc -O -target arm64-apple-macos13.0  -framework AppKit -framework WebKit "${SRC[@]}" -o "$TMP/arm64"
  swiftc -O -target x86_64-apple-macos13.0 -framework AppKit -framework WebKit "${SRC[@]}" -o "$TMP/x86_64"
  lipo -create "$TMP/arm64" "$TMP/x86_64" -output "$BIN"
  rm -rf "$TMP"
else
  swiftc -O -framework AppKit -framework WebKit "${SRC[@]}" -o "$BIN"
fi

if [ ! -f Resources/GuitarCHUD.icns ]; then
  echo "==> Generating app icon"
  ./Icon/make-icon.sh >/dev/null
fi

cp Resources/ui.html "$OUT/Contents/Resources/ui.html"
cp Resources/GuitarCHUD.icns "$OUT/Contents/Resources/GuitarCHUD.icns"

# Ad-hoc signing gives the app a stable identity, so the one-time Automation
# permission you grant survives future rebuilds.
codesign --force --sign - --identifier com.willseiple.guitarhud "$OUT" 2>/dev/null

echo "==> Done: $OUT  [$(lipo -archs "$BIN")]"

if [ "$SHARE" = "1" ]; then
  ZIP="$DEST/GuitarCHUD.zip"
  rm -f "$ZIP"
  # ditto is the archiver that keeps a bundle's symlinks and signature intact.
  ditto -c -k --sequesterRsrc --keepParent "$OUT" "$ZIP"
  echo "==> Shareable archive: $ZIP  ($(du -h "$ZIP" | cut -f1))"

  # A disk image gives the familiar "drag onto Applications" window; a zip just
  # drops a loose app in Downloads.
  DMG="$DEST/GuitarCHUD.dmg"
  rm -f "$DMG"
  STAGE="$(mktemp -d)"
  cp -R "$OUT" "$STAGE/"
  ln -s /Applications "$STAGE/Applications"
  hdiutil create -volname "GuitarCHUD" -srcfolder "$STAGE" -ov -format UDZO -quiet "$DMG"
  rm -rf "$STAGE"
  echo "==> Disk image:        $DMG  ($(du -h "$DMG" | cut -f1))"
  echo
  echo "    Send either one (the .dmg gives the drag-onto-Applications window)."
  echo "    Both are ad-hoc signed rather than notarized, so on the other Mac"
  echo "    Gatekeeper refuses the app until they clear the quarantine flag:"
  echo
  echo "      xattr -dr com.apple.quarantine /Applications/GuitarCHUD.app"
  echo
fi

if [ "$WAS_RUNNING" = "1" ]; then
  echo "==> Relaunching"
  open "$OUT"
fi
