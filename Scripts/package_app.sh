#!/usr/bin/env bash
# Builds SkillsManager with SwiftPM and wraps the binary in an ad-hoc signed .app bundle.
# Usage: Scripts/package_app.sh [debug|release]
set -euo pipefail

CONF=${1:-release}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

APP_NAME="SkillsManager"
DISPLAY_NAME="Skills Manager"
BUNDLE_ID=${BUNDLE_ID:-dev.ryangan.skillsmanager}
MARKETING_VERSION=${MARKETING_VERSION:-0.1.0}
BUILD_NUMBER=${BUILD_NUMBER:-1}

swift build -c "$CONF" --product "$APP_NAME"
BIN_DIR=$(swift build -c "$CONF" --show-bin-path)

APP="$ROOT/build/${APP_NAME}.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>${DISPLAY_NAME}</string>
    <key>CFBundleDisplayName</key><string>${DISPLAY_NAME}</string>
    <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
    <key>CFBundleExecutable</key><string>${APP_NAME}</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${MARKETING_VERSION}</string>
    <key>CFBundleVersion</key><string>${BUILD_NUMBER}</string>
    <key>LSMinimumSystemVersion</key><string>15.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

xattr -cr "$APP"
codesign --force --sign - "$APP" >/dev/null
echo "Created $APP"
