#!/bin/bash
# install.sh — build release + package + install Sherpa Island.app to /Applications
#
# NOTE: Reverted from self-signed stable cert back to ad-hoc.
# The stable cert variant broke `.fullScreenAuxiliary` behavior on
# macOS Sequoia — the notch became invisible over full-screen Spaces.
# Ad-hoc signing keeps full-screen visibility working at the cost of
# requiring an Accessibility re-grant on each reinstall (TCC entries
# are tied to the ad-hoc cdhash which changes per build).
set -e
cd "$(dirname "$0")"

APP_NAME="Sherpa Island.app"
APP_PATH="/tmp/$APP_NAME"
DEST="/Applications/$APP_NAME"

echo "=== Release build ==="
swift build -c release

echo "=== Bundle ==="
rm -rf "$APP_PATH"
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"
cp .build/arm64-apple-macosx/release/SherpaIsland "$APP_PATH/Contents/MacOS/SherpaIsland"
cp Resources/icon-1024.png "$APP_PATH/Contents/Resources/AppIcon.png" 2>/dev/null || true

cat > "$APP_PATH/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>SherpaIsland</string>
    <key>CFBundleIdentifier</key><string>com.sherpa.SherpaIsland</string>
    <key>CFBundleName</key><string>Sherpa Island</string>
    <key>CFBundleDisplayName</key><string>Sherpa Island</string>
    <key>CFBundleShortVersionString</key><string>0.2.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>LSUIElement</key><true/>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSAppleEventsUsageDescription</key><string>Control Macs Fan Control + macOS tools.</string>
    <key>NSCalendarsUsageDescription</key><string>Show next calendar event in notch.</string>
    <key>NSCalendarsFullAccessUsageDescription</key><string>Read upcoming events.</string>
    <key>NSLocationWhenInUseUsageDescription</key><string>Weather widget.</string>
    <key>NSAppleMusicUsageDescription</key><string>Now-playing in notch.</string>
</dict>
</plist>
PLIST

echo "=== Codesign + quarantine clear ==="
codesign --force --deep --sign - "$APP_PATH"
xattr -dr com.apple.quarantine "$APP_PATH"

echo "=== Install ==="
pkill -f SherpaIsland 2>/dev/null || true
sleep 1
mv "$DEST" "$HOME/.Trash/" 2>/dev/null || true
ditto "$APP_PATH" "$DEST"

echo "=== Launch ==="
open "$DEST"
sleep 1
pgrep -fl SherpaIsland | head -1

echo "✓ Installed at $DEST"
