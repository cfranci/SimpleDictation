# Asset Capture Runbook (Armada stitched output, 2026-07-08)

> Executed 2026-07-08: menubar.png, floating-mic.png, typing.png, og.png, poster.png captured live. Demo video capture needs output volume up for the say->mic loopback (Mac was muted at 0).

# SimpleDictation — Asset Capture RUNBOOK (source-verified)

Every technical claim below was checked against the real source in `/Users/cf/Projects/SimpleDictation/Sources/` and tested live on this Mac this session. Corrections to the attempts are called out inline. The app is the owner's running daily driver (PID 33428, Debug build) — **never quit or kill it**; only write the trigger file. If it dies: `open -a SimpleDictation`.

Scratch: `/tmp/sd-capture`  •  Finals: `/Users/cf/Projects/SimpleDictation/site/assets/` (already exists; five stills already live there).

---

## 0. Source-verified facts (do not re-derive; these are checked)

- **Trigger file** (`TriggerWatcher.swift:11`): `~/Library/Application Support/SimpleDictation/trigger`. Watcher is `DispatchSource.makeFileSystemObjectSource` on `[.write,.extend,.delete,.rename]` (line 38-40). Only the FIRST whitespace token is used, lowercased (`AppDelegate.handleExternalCommand`, line 282+). Commands: `start` | `stop` | `toggle` | `enter`. **Write (not append) with a unique nonce** so two identical commands both register as a change.
- **`isEnabled` guard is real** (`AppDelegate.swift:284`, `StatusBarController.swift:543`): if the mic is toggled Off, EVERY trigger command is silently dropped. Verify it is On before any pass.
- **Double-tap = Enter, no separate command** (`AppDelegate.swift:290`): a `start` fired within `0.4s` of a `stop` calls `pressEnter()`. So the video's Enter beat is exactly `trig stop; sleep 0.2; trig start` — NOT `enter` twice, NOT stop/start/stop/start. (Opus modeled this correctly; sonnet-a/sonnet-b/haiku did not.)
- **Paste is CLIPBOARD Cmd+V, not per-character typing** (`SpeechManager.pasteText`, lines 1028-1063: `NSPasteboard.clearContents` + `setString` + CGEvent `virtualKey:55`(cmd)/`virtualKey:9`(v) with `.maskCommand`). Confirmed by reading the function. **Consequence for the video: text lands ALL AT ONCE via paste. Any storyboard promising char-by-char typing is wrong and is corrected below.**
- **Incremental mode is OFF by default** (`SpeechManager.swift:45`: `incrementalMode = false // accumulate all, paste on stop`). So with the default engine, text appears in one paste ~a few seconds after `stop`. Do not script a live streaming-text beat.
- **Current engine = `distil-large-v3`** (verified: `defaults read com.simpledictation.app dictationEngine`). Post-`stop` latency ~5s — a natural "processing" pause in the video. For instant stills, switch to Apple Speech via the right-click menu (do NOT assume Apple is already selected — that was haiku's mistake; and `defaults write` does NOT hot-swap the running app, so use the menu).
- **Status item: left-click STARTS recording, right-click OPENS the engine menu** (`StatusBarController.swift:725` `button.action=statusBarButtonClicked`; `:729` local monitor on `.rightMouseDown` -> `:733` `menu.popUp`). So to capture `menubar.png`, RIGHT-click the status item / floating mic. (Sonnet-a discovered this correctly.)
- **Floating mic is a draggable NSPanel** (`FloatingMicWindow.swift:5`, `level=.floating`), position persisted in `UserDefaults` keys `floatingMicX`/`floatingMicY` (lines 19-20, 92-93). Re-derive its position every session (read those keys or pixel-scan); do not hardcode.
- **Tahoe screencapture does NOT return transparent PNGs.** I tested this session: `screencapture -x -R"0,0,400,40"` of the menu bar -> every sampled pixel alpha=255, fully opaque. **Sonnet-b's central premise ("PNG mode captures pre-compositor buffers, menu bars have alpha=0, must record video + extract frames") is FALSE.** Use plain `screencapture -R` for menu bar and menus. The one legitimately useful bit from sonnet-b is `screencapture -l <windowID>` as an OPTIONAL shortcut for the floating mic, not a requirement.
- **Volume = 0 on this Mac right now** (verified: `osascript -e 'output volume of (get volume settings)'` -> `0`). The `say`->speaker->mic loopback CANNOT work until output volume > 0 AND output device is built-in speakers (not AirPods/BT) AND input is the built-in mic. This is why sonnet-a honestly did not fabricate a demo.mp4. **Do not silently produce empty stills/video.** Preflight-check volume and either raise it or use the documented loopback fallback.
- **Displays**: main = built-in Retina 3456x2234 px (1728x1117 pt @2x); external = 1920x1080 at point-origin roughly `-1920,0`. `screencapture -R` takes POINTS; PNG comes out @2x. Confirm which display the app's floating mic is on before capturing and set the stage rect accordingly (do not blindly trust the "-1920,0,2056,1329" from one attempt — that geometry was not reproducible here; the real assets on disk are 712x1600 etc.).
- **Real on-disk asset dimensions** (verified via sips, these are the target manifest): `menubar.png` 712x1600, `floating-mic.png` 260x260, `typing.png` 2200x600, `og.png` 1200x630, `poster.png` 1280x720. `demo.mp4`/`demo.gif` not yet produced.
- **Tools present**: `/opt/homebrew/bin/{ffmpeg,magick,cliclick}`, `/usr/bin/say`, `/usr/sbin/screencapture`, `/usr/bin/osascript`. Good `say` voice: **Samantha** (en_US, transcribes cleanly). `silenceHallucinations` is already built into `SpeechManager` (source-confirmed), so "thanks for watching"-style hallucinations won't be injected.
- **Menus ignore synthetic Esc on Tahoe**: dismiss context menus by clicking empty desktop, not `key code 53`.

```bash
# ---- setup block: run first ----
export SD_TRIG="$HOME/Library/Application Support/SimpleDictation/trigger"
export SD_SCR=/tmp/sd-capture
export SD_OUT=/Users/cf/Projects/SimpleDictation/site/assets
mkdir -p "$SD_SCR" "$SD_OUT"

trig() { printf '%s %s\n' "$1" "$(date +%s%N)" > "$SD_TRIG"; }   # WRITE + nonce (never append)
pflight() {  # preflight: app alive, mic enabled, volume sane
  pgrep -x SimpleDictation >/dev/null || { echo "APP DOWN"; open -a SimpleDictation; sleep 2; }
  local v; v=$(osascript -e 'output volume of (get volume settings)')
  echo "output volume = $v  (0 => say->mic loopback WILL FAIL, see loopback fallback)"
}
pflight

# Derive the floating mic point-position for THIS session (persisted, draggable):
MICX=$(defaults read com.simpledictation.app floatingMicX 2>/dev/null)
MICY_BL=$(defaults read com.simpledictation.app floatingMicY 2>/dev/null)  # bottom-left origin, AppKit y-up
echo "floatingMic origin (AppKit): x=$MICX y=$MICY_BL  -> convert per its display before cliclick"
```

---

## 1. Clean stage + restore discipline (record every tweak)

```bash
# SAVE state
VOL_WAS=$(osascript -e 'output volume of (get volume settings)')
# Do Not Disturb ON — kills notification banners at the SOURCE instead of racing them
shortcuts run "Turn On Do Not Disturb" 2>/dev/null || \
  defaults -currentHost write com.apple.controlcenter Focus -bool true 2>/dev/null || \
  echo "MANUAL: Control Center > Focus > Do Not Disturb ON"
# Hide desktop icons (also restores the menu bar on fullscreen spaces)
defaults write com.apple.finder CreateDesktop -bool false && killall Finder
osascript -e 'tell application "Finder" to activate'   # menu bar visible if iTerm was fullscreen
osascript -e 'tell application "System Events" to keystroke "h" using {command down, option down}' 2>/dev/null
sleep 1
/usr/sbin/screencapture -x "$SD_SCR/stage-check.png"   # eyeball: no icons, no banners, bar visible
```

---

## 2. Locate the UI (pixel-scan, don't trust AX)

AX/CGWindowList menu-bar coordinates are unreliable on macOS 26. Prefer the persisted `floatingMicX/Y` from step 0; verify by pixel-scanning a screenshot with PIL (sonnet-a's cluster method, which actually produced the real 260x260 crop — more reliable than a magick threshold diff because the audio ring animates).

```bash
# Grab a wide crop around where the mic lives, then cluster its color.
/usr/sbin/screencapture -x "$SD_SCR/scan.png"
python3 - "$SD_SCR/scan.png" <<'PY'
import sys; from PIL import Image
im = Image.open(sys.argv[1]).convert("RGBA"); W,H = im.size
# idle mic = dark circle; recording = red/orange. Cluster whichever is present.
hits=[]
for y in range(0,H,2):
  for x in range(0,W,2):
    r,g,b,a = im.getpixel((x,y))
    if (r>150 and g<110 and b<90) or (30<r<80 and 30<g<80 and 30<b<80):
      hits.append((x,y))
if hits:
  xs=[p[0] for p in hits]; ys=[p[1] for p in hits]
  # @2x px -> point center (halve). Add display origin if on external.
  print(f"mic px center: {sum(xs)//len(xs)},{sum(ys)//len(ys)}  -> pt: {sum(xs)//len(xs)//2},{sum(ys)//len(ys)//2}")
PY
```
Use that point center as `MB_X,MB_Y` for `cliclick`. If a click misses, re-scan and retry — never proceed on assumption.

---

## 3. Screenshot (b) — `floating-mic.png` (glowing, mid-recording, target 260x260)

```bash
trig stop; sleep 0.6            # ensure idle
# Feed audio so the level ring lights (needs volume>0; else the ring is idle — acceptable static glow)
[ "$VOL_WAS" != "0" ] || osascript -e 'set volume output volume 60'
trig start; sleep 0.4
say -v Samantha "testing the microphone" &
sleep 0.7
# Point-rect around the mic (~130x130 pt from step 2), padded:
/usr/sbin/screencapture -x -R"${MB_X_LEFT},${MB_Y_TOP},130,130" "$SD_SCR/floating-mic-raw.png"
wait; trig stop
osascript -e "set volume output volume ${VOL_WAS}"
magick "$SD_SCR/floating-mic-raw.png" -trim +repage -bordercolor none -border 16 "$SD_OUT/floating-mic.png"
```
OPTIONAL shortcut (portable across displays): capture by window ID instead of a rect —
```bash
# compile once: a CGWindowList query filtered by SD PID -> the layer-3 (floating) window id
screencapture -x -l "$MICWINID" "$SD_SCR/floating-mic-raw.png"
# if -l adds a white bg: magick ... -fuzz 10% -transparent white ...
```
Verify the ring is lit (reopen the raw). If idle, nudge the `sleep` up and retry.

---

## 4. Screenshot (a) — `menubar.png` (engine menu open, target ~712x1600)

RIGHT-click opens the menu (left-click would start recording). Menus ignore synthetic Esc.

```bash
osascript -e 'tell application "Finder" to activate'; sleep 0.4
cliclick rc:${MB_X},${MB_Y}          # RIGHT-click the status item / floating mic
sleep 0.7
/usr/sbin/screencapture -x "$SD_SCR/menu-check.png"   # VERIFY the engine list dropdown is showing
# Menu drops down; height ~800pt for 10 engines + settings. Crop from the check shot.
/usr/sbin/screencapture -x -R"${MENU_X},0,360,800" "$SD_SCR/menubar-raw.png"
magick "$SD_SCR/menubar-raw.png" -trim +repage -bordercolor none -border 12 "$SD_OUT/menubar.png"
cliclick c:600,700                   # dismiss by clicking empty desktop (NOT Esc)
```
Expected content: "Simple Dictation" header, Status, Trigger modifiers, Microphone, Language, the Engine list (Apple Speech through the Whisper family + Moonshine, current engine checked), Incremental Mode, Clipboard Cycling. If the check shows no menu, the click missed — re-scan (step 2) and retry.

---

## 5. Screenshot (c) — `typing.png` (dictated text in TextEdit, target 2200x600)

Preferred: a REAL dictation via trigger + `say` (proves the app). Requires volume>0 and the speaker->mic loopback (see fallback). For an instant, reliable still, switch the engine to Apple Speech via the right-click menu first (distil-large-v3 adds ~5s).

```bash
[ "$VOL_WAS" != "0" ] || osascript -e 'set volume output volume 65'
open -a TextEdit; sleep 1.2
osascript -e 'tell application "TextEdit" to make new document' \
          -e 'tell application "TextEdit" to set bounds of window 1 to {200,120,1400,700}'
cliclick c:700,400; sleep 0.3        # focus the document body
trig start; sleep 0.5
say -v Samantha "Hey, this text was typed by my voice. Simple dictation runs one hundred percent on my Mac."
sleep 0.8
trig stop
sleep 6                              # distil-large-v3 transcribes + pastes (ALL AT ONCE via Cmd+V)
# VERIFY text actually landed before shooting (paste can fail silently)
TXT=$(osascript -e 'tell application "TextEdit" to get text of document 1')
echo "TextEdit now: [$TXT]"
if [ -n "$TXT" ]; then
  /usr/sbin/screencapture -x -R"$(( 200 )),120,1200,580" "$SD_SCR/typing-raw.png"
  magick "$SD_SCR/typing-raw.png" -trim +repage -bordercolor none -border 10 "$SD_OUT/typing.png"
else
  echo "NO TEXT -> see loopback fallback (volume=0 or wrong audio route)"
fi
osascript -e "set volume output volume ${VOL_WAS}"
```

**Loopback fallback (this is the real gap on a volume=0 Mac):**
1. Route: built-in speakers as output, built-in mic as input. `SwitchAudioSource -s "MacBook Pro Speakers"` if installed, else System Settings > Sound. Raise output to ~65 and input sensitivity up. Re-run.
2. **Cleanest, most authentic loopback: install BlackHole** (`brew install blackhole-2ch`), create a Multi-Output/aggregate so `say` feeds the input directly (no acoustic path, no echo, works at volume 0). Set SD's input (Microphone submenu) to BlackHole, `say -v Samantha ...`, restore afterward. This is the only reliable real-dictation path when the room/route can't loop.
3. Static-still-only last resort: `osascript -e 'tell application "TextEdit" to set text of document 1 to "Hey, this text was typed by my voice..."'`. Honest note: this makes `typing.png` a mock of the output, not a live capture — use only if 1/2 are impossible, and prefer real audio for the video where the ring reaction matters.

---

## 6. Demo video (20-25s) — one continuous recording, headless-driven

CORRECTED storyboard: text appears via a SINGLE clipboard paste after `stop`, NOT char-by-char. The ~5s distil latency is the natural "processing" beat. Preflight volume; if 0 and no BlackHole, the video is BLOCKED — say so, do not emit an empty file.

| t (s) | beat | driver |
|---|---|---|
| 0-3 | clean stage, empty TextEdit, idle mic | (nothing) |
| 3 | mic glows ON | `trig start` |
| 3.5-8 | sentence spoken, ring reacts | `say -v Samantha "..."` |
| 8.5 | release | `trig stop` |
| 9-14 | ~5s processing, then text PASTES in all at once | app pastes |
| 15 | Enter beat (new line) | `trig stop; sleep 0.2; trig start` |
| 15.5-22 | cursor on new line, hold final frame | (nothing) |

```bash
V=$(osascript -e 'output volume of (get volume settings)')
if [ "$V" = "0" ]; then echo "VOLUME=0 -> demo BLOCKED. Raise volume or use BlackHole (step 5). Not producing an empty file."; else
osascript -e 'set volume output volume 65'
open -a TextEdit; sleep 1
osascript -e 'tell application "TextEdit" to make new document' \
          -e 'tell application "TextEdit" to set bounds of window 1 to {200,120,1400,800}'
trig stop
( sleep 3;   trig start
  sleep 0.5; say -v Samantha "Simple dictation turns my voice into text, anywhere on my Mac."
  sleep 0.5; trig stop
  sleep 6.5; trig stop; sleep 0.2; trig start   # -> Enter (new line)
  sleep 0.3; trig stop ) &
STORY=$!
# Prefer -V (macOS 14+); footnote fallback below if unavailable
/usr/sbin/screencapture -x -v -V 24 -R"${STAGE}" "$SD_SCR/demo-raw.mov" || {
  /usr/sbin/screencapture -x -v -R"${STAGE}" "$SD_SCR/demo-raw.mov" & REC=$!; sleep 24; kill -INT $REC; wait $REC 2>/dev/null; }
wait $STORY
osascript -e "set volume output volume ${V}"
fi
```

### ffmpeg post — H.264 <3MB, poster, GIF
```bash
ffmpeg -y -ss 2.5 -i "$SD_SCR/demo-raw.mov" -t 21 \
  -vf "scale=1280:-2:flags=lanczos,fps=30" \
  -c:v libx264 -profile:v high -pix_fmt yuv420p -movflags +faststart -crf 26 -preset slow -an "$SD_OUT/demo.mp4"
SZ=$(stat -f%z "$SD_OUT/demo.mp4"); echo "demo.mp4 = $((SZ/1024)) KB"
if [ "$SZ" -gt 3145728 ]; then     # two-pass ~1050kbps -> ~2.75MB for 21s
  ffmpeg -y -ss 2.5 -i "$SD_SCR/demo-raw.mov" -t 21 -vf "scale=1280:-2:flags=lanczos,fps=30" -c:v libx264 -b:v 1050k -pass 1 -an -f mp4 /dev/null && \
  ffmpeg -y -ss 2.5 -i "$SD_SCR/demo-raw.mov" -t 21 -vf "scale=1280:-2:flags=lanczos,fps=30" -c:v libx264 -b:v 1050k -pass 2 -pix_fmt yuv420p -movflags +faststart -an "$SD_OUT/demo.mp4"
  rm -f ffmpeg2pass-0.log*
fi
# poster at a frame where the pasted text is visible (~t=13s of raw)
ffmpeg -y -ss 13 -i "$SD_SCR/demo-raw.mov" -frames:v 1 -vf "scale=1280:-2:flags=lanczos" "$SD_OUT/poster.png"
# 11fps looping GIF (palette two-pass)
ffmpeg -y -ss 3 -i "$SD_SCR/demo-raw.mov" -t 12 \
  -vf "fps=11,scale=720:-1:flags=lanczos,split[s0][s1];[s0]palettegen[p];[s1][p]paletteuse" "$SD_OUT/demo.gif"
```

---

## 7. `og.png` — 1200x630 social card (already on disk; regenerate rule)

Use an absolute font FILE path — never a font name (magick silently falls back). Draw the mic as vector primitives, never an emoji glyph (SFNS/Helvetica can't render color emoji; it renders a box).

```bash
magick -size 1200x630 gradient:'#1A1210'-'#0C0A09' \
  -font /System/Library/Fonts/Helvetica.ttc -pointsize 92 -fill '#FFFFFF' \
  -gravity NorthWest -annotate +80+150 'SimpleDictation' \
  -pointsize 40 -fill '#E7C9B8' -annotate +82+280 'Hold. Talk. It types. On-device.' \
  -fill '#FF6A2C' -draw "roundrectangle 80,470 300,560 18,18" \
  -pointsize 40 -fill '#0C0A09' -gravity NorthWest -annotate +112+492 '$4.20 once' \
  "$SD_OUT/og.png"
# optional: composite the real mic still into the right third
magick "$SD_OUT/og.png" \( "$SD_OUT/floating-mic.png" -resize 300x \) -gravity East -geometry +90+0 -composite "$SD_OUT/og.png"
```

---

## 8. Restore EVERYTHING (mandatory — owner's daily driver)

```bash
defaults write com.apple.finder CreateDesktop -bool true && killall Finder
shortcuts run "Turn Off Do Not Disturb" 2>/dev/null || defaults -currentHost write com.apple.controlcenter Focus -bool false 2>/dev/null || echo "MANUAL: Focus > DND OFF"
osascript -e "set volume output volume ${VOL_WAS:-0}"
osascript -e 'tell application "System Events" to keystroke "h" using {command down, option down}' 2>/dev/null
open -a iTerm                         # if it was fullscreen
trig stop                            # leave trigger idle
pgrep -x SimpleDictation >/dev/null && echo "app STILL OK" || open -a SimpleDictation
```

---

## 9. Verify (enforce the manifest + the <3MB budget)

```bash
for f in menubar floating-mic typing poster og; do
  [ -f "$SD_OUT/$f.png" ] && echo "$f.png  $(magick identify -format '%wx%h' "$SD_OUT/$f.png")" || echo "MISSING $f.png"
done
[ -f "$SD_OUT/demo.mp4" ] && echo "demo.mp4 $(( $(stat -f%z "$SD_OUT/demo.mp4")/1024 ))KB (must be <3072)" || echo "demo.mp4 NOT PRODUCED (volume-blocked -> see step 5/6)"
[ -f "$SD_OUT/demo.gif" ] && echo "demo.gif $(( $(stat -f%z "$SD_OUT/demo.gif")/1024 ))KB" || echo "demo.gif pending"
```
Target manifest (verified real dims): `menubar.png` 712x1600, `floating-mic.png` 260x260, `typing.png` 2200x600, `og.png` 1200x630, `poster.png` 1280x720, plus `demo.mp4` (<3MB) and `demo.gif`.

---

## Reliability rules baked in
- **Verify, never assume**: after every trigger/click, re-screenshot and read TextEdit text before the real capture. UI located by persisted `floatingMicX/Y` + PIL pixel-cluster, not AX.
- **Trigger is exact**: `printf '%s %s\n' cmd $(date +%s%N) > trigger` (WRITE + nonce, first token, lowercased). Enter = `stop; sleep 0.2; start`. Mic must be `isEnabled` or commands drop silently.
- **Paste is one clipboard Cmd+V** — the demo shows text appearing all at once after ~5s, not typed char-by-char.
- **Tahoe screencapture PNGs are opaque** (tested) — use plain `screencapture -R`; `-l <windowID>` is an optional convenience for the floating mic only.
- **Volume=0 is a hard blocker** — preflight it; use BlackHole for authentic loopback, or honestly report the video as blocked rather than emit an empty file.
- **The running app is never quit/killed**; only the trigger file is written; relaunch with `open -a SimpleDictation`.
- No em dashes used.

## Open questions
- demo.mp4/demo.gif are still not produced: on this Mac output volume=0, so the say->mic loopback fails. Producing a genuine demo requires either raising volume and confirming the built-in speaker/mic route, or installing BlackHole (brew install blackhole-2ch) to feed say straight into the input. Needs owner go-ahead on installing BlackHole or a manual human-voice recording session.
- The exact stage rect / which physical display the floating mic currently sits on was not pinned down this session (main is Retina 3456x2234, external 1920x1080). The runbook derives it live via floatingMicX/Y + pixel-scan; a single confirmed STAGE value would let steps 3/4/6 run non-interactively.
- The five existing stills on disk (menubar 712x1600 etc.) were captured in a prior session; whether they used a real dictation for typing.png or the AppleScript/text-injection mock is unverified. If authenticity matters for the landing page, typing.png should be re-shot via the BlackHole loopback path.