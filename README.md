# SimpleDictation

A macOS menu bar app that turns your voice into text. Hold a key, talk, release, and the transcription gets pasted wherever your cursor is. Works in any app.

## How It Works

1. You hold down the **fn** key (or option key)
2. Talk into your mic
3. Release the key
4. The text gets typed out wherever your cursor is -- chat boxes, text editors, search bars, anywhere

Double-tap the key to press Enter (submits forms, sends messages).

There's also a floating mic button on screen you can click instead of using the hotkey.

## Setup (Mac)

### Prerequisites

- macOS 14.0 or later
- [Homebrew](https://brew.sh) installed
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) installed:

```bash
brew install xcodegen
```

- Xcode Command Line Tools:

```bash
xcode-select --install
```

### Install and Build

```bash
git clone https://github.com/cfranci/SimpleDictation.git
cd SimpleDictation
./build.sh
```

The build script generates the Xcode project, compiles the app, and launches it automatically.

### Grant Permissions

On first launch, macOS will ask for three permissions. Say yes to all of them:

1. **Microphone** -- so it can hear you
2. **Accessibility** -- so it can type text into other apps and handle the clipboard history
3. **Speech Recognition** -- for the Apple Speech engine

If you accidentally denied one, go to System Settings > Privacy & Security and enable them for SimpleDictation.

### That's It

The app lives in your menu bar (top right of your screen). Click the icon to switch engines, change your hotkey, or adjust settings. Right-click the floating mic button for the same menu.

## Choosing an Engine

The app comes with multiple speech-to-text engines. You can switch between them from the menu bar.

| Engine | Download Size | Speed | Accuracy | Notes |
|--------|--------------|-------|----------|-------|
| Apple Speech | Nothing to download | Instant | Good | Uses built-in macOS dictation |
| Whisper Tiny | ~40 MB | ~1s | Fair | Fastest local model |
| Whisper Base | ~140 MB | ~2s | Good | Good balance |
| Whisper Small | ~460 MB | ~4s | Better | Recommended for most people |
| Whisper Medium | ~1.5 GB | ~7s | Great | Best for long-form |
| Distil-Whisper Large v3 | ~594 MB | ~5s | Great | High accuracy, reasonable speed |
| Distil-Whisper Large v3 Turbo | ~600 MB | ~9s | Best | Most accurate overall |
| Moonshine Tiny | Bundled | ~1s | Fair | Comes with the app |

**Start with Apple Speech** -- it works instantly with no downloads. If you want better accuracy, try Whisper Small or Distil-Whisper Large v3.

Models that aren't downloaded yet appear grayed out in the menu. Select one to start the download. You'll see a notification when it's ready.

## Controls

| Action | How |
|--------|-----|
| Record | Hold **fn** key (or option, configurable) |
| Stop and paste | Release the key |
| Submit / press Enter | Double-tap the key |
| Toggle recording | Click the floating mic button |
| Submit via button | Double-click the floating mic button |
| Open settings | Right-click the floating mic button, or click the menu bar icon |

### Clipboard History

SimpleDictation also includes clipboard history. The last 10 things you copied are saved.

- Hold **Cmd**, then tap **V** repeatedly to cycle through your clipboard history
- Works in Chrome, Safari, Notes, TextEdit, and most apps

## Features

- **Hold-to-talk** dictation with automatic paste
- **8 speech engines** from instant to high-accuracy
- **Floating mic button** with recording glow and audio level ring
- **Clipboard history cycling** (last 10 copies, Cmd+V to cycle)
- **Incremental mode** to see partial transcription as you speak
- **16 languages** including English, Spanish, French, Chinese, Japanese
- **Double-tap to submit** for chat boxes and forms
- **Model management** with download progress notifications

## Rebuilding

If you pull updates:

```bash
cd SimpleDictation
git pull
./build.sh
```
