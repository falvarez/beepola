#!/usr/bin/env bash
# Build Beepola for macOS and package it as an ad-hoc signed Beepola.app.
#
#   ./build_macos.sh
#
# Needs lazbuild built against FPC >= 3.2.4 (see docs/PLAN.md); override its
# location with LAZBUILD=/path/to/lazbuild.
set -euo pipefail

cd "$(dirname "$0")"

LAZBUILD=${LAZBUILD:-$HOME/opt/lazarus/lazbuild}
VERSION=1.06.02
APP=Beepola.app
HELP_SRC=Beepola_v1.08.01/help

"$LAZBUILD" Beepola.lpi

rm -rf ./Beepola.app
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Beepola "$APP/Contents/MacOS/Beepola"
printf 'APPL????' > "$APP/Contents/PkgInfo"

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>Beepola</string>
  <key>CFBundleIconFile</key>
  <string>Beepola</string>
  <key>CFBundleIdentifier</key>
  <string>local.beepola.Beepola</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>Beepola</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$VERSION</string>
  <key>CFBundleVersion</key>
  <string>$VERSION</string>
  <key>LSMinimumSystemVersion</key>
  <string>11.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
EOF

# Icon: Beepola.ico tops out at 48x48, so the larger sizes are upscaled
ICONSET=$(mktemp -d)/Beepola.iconset
mkdir -p "$ICONSET"
for spec in 16:16x16 32:16x16@2x 32:32x32 64:32x32@2x 128:128x128 256:128x128@2x 256:256x256; do
  sips -s format png -z "${spec%%:*}" "${spec%%:*}" Beepola.ico --out "$ICONSET/icon_${spec#*:}.png" > /dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/Beepola.icns"

# Help: TSTMainWnd.mnuHelpOnlineClick opens Resources/help/index.html, or the
# online help when it is missing
if [ -d "$HELP_SRC" ]; then
  cp -R "$HELP_SRC" "$APP/Contents/Resources/help"
else
  echo "warning: $HELP_SRC not found; the Help menu will open the online help" >&2
fi

codesign --force --sign - "$APP"
echo "Built $APP"
