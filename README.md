# SimpleDictation

A macOS menu bar app that turns your voice into text. Hold a key, talk, release, and the transcription gets pasted wherever your cursor is. Works in any app.

## Download

Requires macOS 14.0 or later.

**[v1.3.0](https://github.com/cfranci/SimpleDictation/releases/tag/v1.3.0)** is the last fully free release ([DMG](https://github.com/cfranci/SimpleDictation/releases/download/v1.3.0/SimpleDictation-1.3.0.dmg)). It is not a trial and it is not notarized, so macOS warns the first time you open it. It stays available.

**1.4.0** is the maintained build. Every engine works for 14 days, then Apple Speech stays free and $4.20 once (Stripe) unlocks Whisper, Moonshine, and Whistle on two Macs. A Mac that already used v1.3.0 stays unlocked. The notarized 1.4.0 DMG is not published yet. Until [docs/GO_LIVE.md](docs/GO_LIVE.md) is done, build from source or keep using v1.3.0. Updates are new DMG downloads. There is no in-app auto-updater.

## How It Works

1. You hold down the **fn** key (or option key)
2. Talk into your mic
3. Release the key
4. The text gets pasted wherever your cursor is -- chat boxes, text editors, search bars, anywhere

Double-tap the key to press Enter (submits forms, sends messages).

There's also a floating mic button on screen you can click instead of using the hotkey.

## Setup

### Option 1: Download the DMG (recommended)

1. Go to [Releases](https://github.com/cfranci/SimpleDictation/releases/tag/v1.3.0) for the free build, or use the 1.4.0 DMG once it is published
2. Download the DMG
3. Open the DMG and drag SimpleDictation to Applications
4. Launch from Applications

### Option 2: Build from source

Requires [Homebrew](https://brew.sh), [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`), and Xcode Command Line Tools (`xcode-select --install`).

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
| Apple Speech | Nothing to download | Instant | Good | Uses built-in macOS dictation. Stays free after the trial |
| Whistle | Bundled (17 MB) | ~1s | Fair | On-device, no download. Premium after the 14-day trial |
| Whisper Tiny | ~40 MB | ~1s | Fair | Fastest local Whisper |
| Whisper Base | ~140 MB | ~2s | Good | Good balance |
| Whisper Small | ~460 MB | ~4s | Better | Recommended for most people |
| Whisper Medium | ~1.5 GB | ~7s | Great | Best for long-form |
| Distil-Whisper Large v3 | ~594 MB | ~5s | Great | High accuracy, reasonable speed |
| Distil-Whisper Large v3 Turbo | ~600 MB | ~9s | Best | Most accurate overall |
| Whisper Large v3 Turbo | ~1.5 GB | ~5s | Best | Latest OpenAI model, streaming-optimized |
| Whisper Large v3 Turbo (632MB) | ~632 MB | ~5s | Best | Compressed version, best bang for buck |
| Moonshine Tiny | Bundled | ~1s | Fair | Comes with the app |

**Start with Apple Speech** -- it works instantly with no downloads. If you select a model that hasn't been downloaded yet, the app uses Apple Speech as a fallback while the model downloads in the background, then switches over automatically.

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
- **11 speech engines** from instant to high-accuracy (Apple Speech, Whistle, eight Whisper variants, Moonshine)
- **Floating mic button** with recording glow, audio level ring, and resizable icon (10-50px)
- **Clipboard history cycling** (last 10 copies, Cmd+V to cycle)
- **Incremental mode** to see partial transcription as you speak
- **12 languages**: English (US, UK, Australia), Spanish (Spain and Mexico), French, German, Italian, Portuguese (Brazil), Chinese (Simplified and Traditional), Japanese, Korean, Hindi, Arabic, and Russian. The menu lists those as 16 regional variants
- **Double-tap to submit** for chat boxes and forms
- **Auto-fallback** to Apple Speech while models download
- **Model management** with download progress notifications

## Rebuilding

If you pull updates:

```bash
cd SimpleDictation
git pull
./build.sh
```

## Repository layout

```
Sources/            The macOS app (Swift/AppKit). LicenseManager + Base32 live here too.
site/               Marketing site (index.html, buy.html) + assets/. Deploys to GitHub Pages.
license/            The license-key backend, one subsystem:
  worker/           Cloudflare Worker + D1 schema + wrangler config (deploys to API KING).
  admin/            keys.html, the admin console to view/manage the key database.
  scripts/          gen-keys.mjs, the Ed25519 keygen + batch generator.
  keys/  dist/       Generated key material and batches. GITIGNORED, never committed.
docs/               Planning + ops docs. docs/GO_LIVE.md is the launch checklist. See docs/README.md for the index.
build.sh            Build + launch the app locally.
build-dmg.sh        Assemble the distributable DMG.
project.yml         XcodeGen project definition (app target = Sources/).
```

The app (`Sources/`, `build.sh`, `project.yml`) and the license backend (`license/`) are independent: building the app never touches the backend, and deploying the backend never touches the app.
