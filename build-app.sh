#!/bin/sh
set -eu
cd "$(dirname "$0")"
swift build -c release "$@"
BIN_DIR=$(swift build -c release --show-bin-path "$@")
APP="Daymark.app/Contents"
mkdir -p "$APP/MacOS"
cp "$BIN_DIR/Daymark" "$APP/MacOS/Daymark"
cat > "$APP/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Daymark</string>
<key>CFBundleIdentifier</key><string>local.notch.todos</string>
<key>CFBundleName</key><string>Daymark</string>
<key>CFBundleDisplayName</key><string>Daymark</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSUIElement</key><true/>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - Daymark.app
printf 'Built Daymark.app. Open it to find Daymark in your menu bar.\n'
