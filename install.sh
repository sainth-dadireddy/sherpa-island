#!/bin/bash
# install.sh — build release + package + install Sherpa Island.app to /Applications
#
# Uses a one-time-generated self-signed code signing identity stored in
# the login keychain so TCC grants (Accessibility, etc.) survive
# reinstalls. Ad-hoc signing (--sign -) creates a fresh identity per
# build, silently invalidating every prior grant. The self-signed cert
# is reused for every install; codesign may prompt "Always Allow" the
# first time it accesses the private key — click that once.
set -e
cd "$(dirname "$0")"

APP_NAME="Sherpa Island.app"
APP_PATH="/tmp/$APP_NAME"
DEST="/Applications/$APP_NAME"
SIGN_IDENTITY="Sherpa Island Local Signer"
P12_PASS="sherpa-island-local"

ensure_signing_identity() {
    if /usr/bin/security find-identity -p codesigning 2>/dev/null | grep -q "$SIGN_IDENTITY"; then
        return 0
    fi
    echo "=== One-time setup: generating $SIGN_IDENTITY ==="
    local tmpdir
    tmpdir=$(mktemp -d)
    trap 'rm -rf "$tmpdir"' RETURN

    openssl req -new -newkey rsa:2048 -nodes \
        -keyout "$tmpdir/key.pem" \
        -out "$tmpdir/csr.pem" \
        -subj "/CN=$SIGN_IDENTITY" \
        -days 3650 >/dev/null 2>&1

    cat > "$tmpdir/ext.cnf" <<'EXT'
[v3]
basicConstraints=critical,CA:false
keyUsage=critical,digitalSignature
extendedKeyUsage=critical,codeSigning
EXT

    openssl x509 -req -days 3650 \
        -in "$tmpdir/csr.pem" \
        -signkey "$tmpdir/key.pem" \
        -out "$tmpdir/cert.pem" \
        -extensions v3 -extfile "$tmpdir/ext.cnf" >/dev/null 2>&1

    # Force legacy PBE so macOS `security import` (pre-modern PBES2)
    # accepts the bundle. -macalg SHA1 + PBE-SHA1-3DES is the magic combo.
    openssl pkcs12 -export \
        -inkey "$tmpdir/key.pem" \
        -in "$tmpdir/cert.pem" \
        -out "$tmpdir/bundle.p12" \
        -name "$SIGN_IDENTITY" \
        -keypbe PBE-SHA1-3DES \
        -certpbe PBE-SHA1-3DES \
        -macalg SHA1 \
        -passout "pass:$P12_PASS" >/dev/null 2>&1

    # -A: grant access to ALL apps without prompting (no per-app ACL hassle).
    # -T flags also add codesign + security explicitly as a belt-and-suspenders.
    /usr/bin/security import "$tmpdir/bundle.p12" \
        -k "$HOME/Library/Keychains/login.keychain-db" \
        -P "$P12_PASS" \
        -A \
        -T /usr/bin/codesign \
        -T /usr/bin/security >/dev/null

    echo "    ✓ $SIGN_IDENTITY created — reused for all future installs."
    echo "    ✓ TCC grants (Accessibility, etc.) will persist across reinstalls."
}

ensure_signing_identity

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
# First codesign call may prompt "Always Allow" for keychain access.
# Click that once — it sticks for the lifetime of the keychain entry.
codesign --force --deep --sign "$SIGN_IDENTITY" "$APP_PATH"
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
