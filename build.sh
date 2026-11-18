#!/bin/bash
set -e
# Without pipefail, `xcodebuild ... | tail` masks a failed build (tail exits 0),
# so the script would sign, install and launch a STALE app. pipefail makes the
# pipeline inherit xcodebuild's failure so set -e aborts before any of that.
set -o pipefail

cd "$(dirname "$0")"

# Vendor/Needle/libneedle.a is stored in Git LFS. If git-lfs wasn't installed when
# the repo was cloned, the file is a small text pointer and the link step fails
# with "unknown file type". Catch that early with a clear message.
NEEDLE_LIB="Vendor/Needle/libneedle.a"
if [ -f "$NEEDLE_LIB" ] && head -c 100 "$NEEDLE_LIB" | grep -q "git-lfs.github.com/spec"; then
  echo "ERROR: $NEEDLE_LIB is a Git LFS pointer, not the real library."
  echo "       Install Git LFS and fetch it:  brew install git-lfs && git lfs install && git lfs pull"
  exit 1
fi

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
