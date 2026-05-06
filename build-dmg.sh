#!/bin/bash
set -e

cd "$(dirname "$0")"

APP_NAME="SimpleDictation"
VERSION=$(grep 'MARKETING_VERSION:' project.yml | head -1 | awk '{print $2}' | tr -d '"')
DMG_NAME="${APP_NAME}-${VERSION}"

echo "==> Building ${APP_NAME} v${VERSION} (Release)..."

# Generate Xcode project
xcodegen generate

# Build Release
xcodebuild -project ${APP_NAME}.xcodeproj -scheme ${APP_NAME} -configuration Release -derivedDataPath build build 2>&1 | tail -5

echo "==> Creating DMG..."

# Clean up temp
rm -rf /tmp/${DMG_NAME}-dmg
mkdir -p /tmp/${DMG_NAME}-dmg

# Copy app
cp -R build/Build/Products/Release/${APP_NAME}.app /tmp/${DMG_NAME}-dmg/

# Clear quarantine
xattr -cr /tmp/${DMG_NAME}-dmg/${APP_NAME}.app 2>/dev/null || true

# Add Applications symlink for drag-and-drop install
ln -s /Applications /tmp/${DMG_NAME}-dmg/Applications

# Create DMG
rm -f ${DMG_NAME}.dmg
hdiutil create -volname "${APP_NAME}" -srcfolder /tmp/${DMG_NAME}-dmg -ov -format UDZO ${DMG_NAME}.dmg

# Clean up temp
rm -rf /tmp/${DMG_NAME}-dmg

echo "==> Created ${DMG_NAME}.dmg ($(du -h ${DMG_NAME}.dmg | cut -f1))"
echo "==> Done!"
