#!/bin/bash
# Ventura (macOS 13) build — Apple Speech only, no SwiftPM deps.
# Builds with Command Line Tools only (swiftc), no full Xcode required.
set -e

cd "$(dirname "$0")"

APP="SimpleDictation.app"
TARGET="x86_64-apple-macos13.0"
SDK="$(xcrun --show-sdk-path)"

echo "==> Compiling (target $TARGET)..."
mkdir -p build
swiftc -O \
  -target "$TARGET" \
  -sdk "$SDK" \
  -o build/SimpleDictation \
  Sources/*.swift \
  -framework Cocoa \
  -framework Speech \
  -framework AVFoundation \
  -framework CoreAudio \
  -framework Combine

echo "==> Assembling app bundle..."
killall SimpleDictation 2>/dev/null || true
sleep 0.3
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp build/SimpleDictation "$APP/Contents/MacOS/SimpleDictation"
cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>            <string>SimpleDictation</string>
    <key>CFBundleDisplayName</key>     <string>Simple Dictation</string>
    <key>CFBundleIdentifier</key>      <string>com.simpledictation.app</string>
    <key>CFBundleVersion</key>         <string>1</string>
    <key>CFBundleShortVersionString</key> <string>1.3.0</string>
    <key>CFBundlePackageType</key>     <string>APPL</string>
    <key>CFBundleExecutable</key>      <string>SimpleDictation</string>
    <key>CFBundleIconFile</key>        <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>  <string>13.0</string>
    <key>LSUIElement</key>             <true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>SimpleDictation needs microphone access for speech-to-text dictation.</string>
    <key>NSSpeechRecognitionUsageDescription</key>
    <string>SimpleDictation needs speech recognition to convert your voice to text.</string>
</dict>
</plist>
PLIST

echo "==> Ad-hoc code signing..."
codesign --force --deep --sign - \
  --entitlements SimpleDictation.entitlements \
  "$APP" 2>/dev/null || codesign --force --deep --sign - "$APP"

echo "==> Clearing quarantine..."
xattr -cr "$APP" 2>/dev/null || true

echo "==> Done: $APP"
echo "    Launch with: open $APP"
