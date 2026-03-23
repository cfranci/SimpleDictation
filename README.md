# SimpleDictation

A lightweight macOS menu bar app for speech-to-text dictation with multiple engine support, clipboard history cycling, and a floating mic button.

## Features

### Dictation
- **Multiple engines**: Apple Speech, WhisperKit (Tiny → Large), Moonshine, Distil-Whisper
- **Hold-to-talk**: Hold fn/option key to record, release to transcribe and paste
- **Double-tap to submit**: Double-tap the hotkey to press Enter (submits chat boxes, forms, etc.)
- **Incremental mode**: See partial transcription as you speak
- **Language support**: 16 languages including English, Spanish, French, Chinese, Japanese, and more

### Floating Mic Button
- Always-visible floating pill UI — works even when menu bar is hidden
- Bright red glow when recording with audio level ring
- Click to toggle recording, double-click to send Enter
- Right-click for full settings menu
- Draggable to any position (remembers location)
- Shows current engine label (W-T, DL3T, SR, etc.)

### Model Management
- Grayed-out models that aren't downloaded locally
- Floating notification when downloading a new model
- Menu items flash while download is in progress
- "Ready" notification when model is available

### Clipboard History Cycling
- System-wide clipboard history (last 10 copies)
- Hold Cmd, press V repeatedly to cycle through history
- Uses macOS Accessibility API for reliable text replacement
- Works in Chrome, Safari, TextEdit, Notes, and most apps
- Falls back gracefully in Terminal

## Requirements

- macOS 14.0+
- Accessibility permission (for clipboard cycling and hotkey)
- Microphone permission
- Speech Recognition permission (for Apple engine)

## Build

```bash
./build.sh
```

Uses [XcodeGen](https://github.com/yonaskolb/XcodeGen) to generate the Xcode project, then builds and launches.

## Engines

| Engine | Size | Speed | Accuracy |
|--------|------|-------|----------|
| Apple Speech | — | Instant | Good |
| Whisper Tiny | ~40MB | ~1s | Fair |
| Whisper Base | ~140MB | ~2s | Good |
| Whisper Small | ~460MB | ~4s | Better |
| Whisper Medium | ~1.5GB | ~7s | Great |
| Distil-Whisper Large v3 | ~594MB | ~5s | Great |
| Distil-Whisper Large v3 Turbo | ~600MB | ~9s | Best |
| Moonshine Tiny | Bundled | ~1s | Fair |

## Hotkeys

- **fn** (default), **option**, or **both**: Hold to record, release to paste
- **Double-tap hotkey**: Press Enter / submit
- **Cmd+V cycling**: Hold Cmd, tap V repeatedly to cycle clipboard history
