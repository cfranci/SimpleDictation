#!/bin/bash
set -e

cd "$(dirname "$0")"

echo "==> Generating Xcode project..."
xcodegen generate

echo "==> Building..."
xcodebuild -project SimpleDictation.xcodeproj -scheme SimpleDictation -configuration Debug -derivedDataPath build build 2>&1 | tail -5

echo "==> Killing old process..."
killall SimpleDictation 2>/dev/null || true
sleep 0.5

echo "==> Copying app..."
rm -rf SimpleDictation.app
cp -R build/Build/Products/Debug/SimpleDictation.app .

echo "==> Clearing quarantine..."
xattr -cr SimpleDictation.app 2>/dev/null || true

echo "==> Launching..."
open SimpleDictation.app

echo "==> Done!"
