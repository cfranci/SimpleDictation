#!/bin/bash
# Build + Developer-ID sign + notarize + staple + DMG, for distributing to anyone.
# Prereqs (one-time):
#   1. A "Developer ID Application" certificate in your keychain
#      (Xcode > Settings > Accounts > Manage Certificates > + > Developer ID Application).
#   2. A notarytool keychain profile with your Apple ID + app-specific password:
#      xcrun notarytool store-credentials SD-notary \
#        --apple-id YOU@EXAMPLE.COM --team-id <TEAMID> --password <app-specific-password>
# Usage: ./notarize-dmg.sh [profile-name]   (default profile: SD-notary)
set -e
set -o pipefail
cd "$(dirname "$0")"

APP="SimpleDictation"
PROFILE="${1:-SD-notary}"
VERSION=$(grep 'MARKETING_VERSION:' project.yml | head -1 | awk '{print $2}' | tr -d '"')
ENTITLEMENTS="SimpleDictation-dist.entitlements"

# --- find the Developer ID Application identity ---
DEVID=$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -1 | sed -E 's/.*"([^"]+)".*/\1/')
if [ -z "$DEVID" ]; then
  echo "ERROR: no 'Developer ID Application' certificate in the keychain."
  echo "Create one: Xcode > Settings > Accounts > Manage Certificates > + > Developer ID Application."
  exit 1
fi
echo "==> Signing identity: $DEVID"

# --- build Release ---
echo "==> Building ${APP} v${VERSION} (Release)..."
xcodegen generate >/dev/null
xcodebuild -project ${APP}.xcodeproj -scheme ${APP} -configuration Release -derivedDataPath build build 2>&1 | tail -3
APPPATH="build/Build/Products/Release/${APP}.app"

# --- sign nested code bottom-up, then the app (hardened runtime + secure timestamp) ---
echo "==> Signing nested frameworks/dylibs..."
if [ -d "$APPPATH/Contents/Frameworks" ]; then
  find "$APPPATH/Contents/Frameworks" -type f -name "*.dylib" -print0 | while IFS= read -r -d '' f; do
    codesign --force --timestamp --options runtime -s "$DEVID" "$f"
  done
  find "$APPPATH/Contents/Frameworks" -maxdepth 1 -name "*.framework" -print0 | while IFS= read -r -d '' fw; do
    codesign --force --timestamp --options runtime -s "$DEVID" "$fw"
  done
fi
echo "==> Signing the app bundle..."
codesign --force --timestamp --options runtime --entitlements "$ENTITLEMENTS" -s "$DEVID" "$APPPATH"
echo "==> Verifying signature..."
codesign --verify --deep --strict --verbose=2 "$APPPATH"
codesign -dv --verbose=4 "$APPPATH" 2>&1 | grep -iE "Authority=|TeamIdentifier|flags" | head -4

# --- notarize (zip -> submit -> wait) ---
echo "==> Submitting to Apple notary service (profile: $PROFILE)..."
rm -f /tmp/${APP}-notary.zip
ditto -c -k --keepParent "$APPPATH" /tmp/${APP}-notary.zip
xcrun notarytool submit /tmp/${APP}-notary.zip --keychain-profile "$PROFILE" --wait

# --- staple the ticket onto the app ---
echo "==> Stapling..."
xcrun stapler staple "$APPPATH"

# --- build + staple the DMG ---
echo "==> Building DMG..."
DMG="${APP}-${VERSION}.dmg"
rm -rf /tmp/${APP}-dmg && mkdir -p /tmp/${APP}-dmg
cp -R "$APPPATH" /tmp/${APP}-dmg/
ln -s /Applications /tmp/${APP}-dmg/Applications
rm -f "$DMG"
hdiutil create -volname "$APP" -srcfolder /tmp/${APP}-dmg -ov -format UDZO "$DMG"
rm -rf /tmp/${APP}-dmg
xcrun stapler staple "$DMG"

echo ""
echo "==> DONE. Notarized + stapled: $DMG ($(du -h "$DMG" | cut -f1))"
echo "==> Gatekeeper check:"
spctl -a -vvv -t install "$DMG" 2>&1 | head -2 || true
