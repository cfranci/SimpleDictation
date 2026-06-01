# SimpleDictation — Ventura (macOS 13) Edition

A macOS menu bar app that turns your voice into text. Hold a key, talk, release, and the transcription gets pasted wherever your cursor is. Works in any app.

> **This is the `macos-13-ventura` fork.** It targets **macOS 13 (Ventura)** and uses the built-in **Apple Speech** engine only. The WhisperKit and Moonshine local AI engines on `main` require macOS 14+ runtime APIs and are not included here. Everything else — hold-to-talk, floating mic, clipboard history, languages, double-tap to submit — works the same.

Requires macOS 13.0 or later.

## How It Works

1. You hold down the **fn** key (or option key)
2. Talk into your mic
3. Release the key
4. The text gets typed out wherever your cursor is -- chat boxes, text editors, search bars, anywhere

Double-tap the key to press Enter (submits forms, sends messages).

There's also a floating mic button on screen you can click instead of using the hotkey.

## Build from source

This fork has **no Swift package dependencies**, so it builds with just the **Xcode Command Line Tools** — full Xcode is not required.

```bash
git clone -b macos-13-ventura https://github.com/cfranci/SimpleDictation.git
cd SimpleDictation
./build-ventura.sh
```

`build-ventura.sh` compiles the sources with `swiftc`, assembles the `.app` bundle, ad-hoc signs it, and is ready to `open SimpleDictation.app`.

> If you have full Xcode + [XcodeGen](https://github.com/yonaskolb/XcodeGen) installed, `./build.sh` still works too — `project.yml` targets macOS 13.

### Grant Permissions

On first launch, macOS will ask for three permissions. Say yes to all of them:

1. **Microphone** -- so it can hear you
2. **Accessibility** -- so it can type text into other apps and handle the clipboard history
3. **Speech Recognition** -- for the Apple Speech engine

If you accidentally denied one, go to System Settings > Privacy & Security and enable them for SimpleDictation.

### That's It

The app lives in your menu bar (top right of your screen). Click the icon to change your hotkey or adjust settings. Right-click the floating mic button for the same menu.

## Speech Engine

This fork uses **Apple Speech** — the built-in macOS dictation engine. Nothing to download, instant, good accuracy, fully on-device for supported languages. Switching engines is a no-op (Apple Speech is the only option on Ventura).

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
- **Apple Speech** engine — instant, on-device, no downloads
- **Floating mic button** with recording glow, audio level ring, and resizable icon (10-50px)
- **Clipboard history cycling** (last 10 copies, Cmd+V to cycle)
- **16 languages** including English, Spanish, French, Chinese, Japanese
- **Double-tap to submit** for chat boxes and forms

## Rebuilding

If you pull updates:

```bash
cd SimpleDictation
git pull
./build-ventura.sh
```
