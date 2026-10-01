#!/bin/bash
set -e

cd "$(dirname "$0")"

echo "==> Generating Xcode project..."
xcodegen generate 2>/dev/null || echo "   (xcodegen not installed; using existing .xcodeproj)"

echo "==> Building..."
xcodebuild -project SimpleDictation.xcodeproj -scheme SimpleDictation -configuration Release -derivedDataPath build build 2>&1 | tail -5

REL="build/Build/Products/Release/SimpleDictation.app"

# Sign with a STABLE identity so the Accessibility (and other TCC) grants survive
# rebuilds. The app's designated requirement then keys on the bundle id + this
# cert, not the per-build cdhash — so you only grant permissions once, ever.
# Falls back to the existing ad-hoc signature if the identity isn't available.
IDENTITY="Apple Development: Created via API (K3RDH3LM7F)"
if security find-identity -v -p codesigning | grep -q "$IDENTITY"; then
  echo "==> Signing with stable identity ($IDENTITY)..."
  codesign --force --deep --sign "$IDENTITY" --entitlements SimpleDictation.entitlements "$REL"
else
  echo "==> WARNING: stable identity not found; leaving ad-hoc signature."
  echo "    Accessibility will need re-granting after this build."
fi

echo "==> Killing old process..."
killall SimpleDictation 2>/dev/null || true
sleep 0.5

# Install to /Applications (the canonical, permissioned copy) AND refresh the
# project-local copy so the two never drift out of sync.
echo "==> Installing to /Applications..."
rm -rf /Applications/SimpleDictation.app
cp -R "$REL" /Applications/SimpleDictation.app
xattr -cr /Applications/SimpleDictation.app

echo "==> Refreshing project copy..."
rm -rf SimpleDictation.app
cp -R "$REL" SimpleDictation.app
xattr -cr SimpleDictation.app

echo "==> Launching..."
open /Applications/SimpleDictation.app

echo "==> Done!"
