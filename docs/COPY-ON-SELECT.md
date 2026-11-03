# SimpleDictation — Copy-on-Select Research (Nov 2026)

Research captured on branch `feature/copy-on-select`. No app code changed yet — this
is the plan to build against.

Goal: highlight text anywhere → it's auto-copied to the clipboard (X11-style), no
Cmd+C. macOS has **no native** copy-on-select, so it must be synthesized on top of an
Accessibility grant (which the app already has).

---

## How every real tool does it (PopClip, SelectCopy, SelectedTextKit)

Two-tier, in priority order:

1. **`AXSelectedText`** — read the highlighted string off the focused AX element.
   Fast, silent, never touches the clipboard. Works in Cocoa apps, Safari, Chromium.
2. **`AXSelectedTextRange` + `AXStringForRange`** — range fallback.
3. **Synthesize Cmd+C** — only when AX returns `nil` (Electron apps, Zotero, some
   terminals). "Borrow the clipboard." Mute the alert volume around the keypress to
   kill the beep; some tools save/restore the prior clipboard (we WANT it on the
   clipboard, so skip the restore).

## SelectCopy's exact recipe (closest analog — it IS this feature)

- `NSEvent` global monitors on `.leftMouseDown` (record point) + `.leftMouseUp`.
- Treat as a selection if drag distance > 4pt (`hypot(dx,dy) > 4`) **or**
  `clickCount >= 2` (double/triple-click).
- Wait **80ms** after mouse-up for the app to settle, then read AX.
- Confirm the Cmd+C fallback worked by checking `NSPasteboard.changeCount` rose
  within **150ms**.
- Per-app skip list: `com.apple.finder` (Cmd+C copies files),
  `com.github.wez.wezterm` (already copies on select / races the write).

## Known gotchas

- **Clipboard clobbering** — the canonical complaint. Mitigate: only the fallback
  touches the clipboard; dedup history; app-exclusion list.
- **Privacy** — reads anything you highlight (incl. password fields). Off by default
  + exclusion list.

---

## Maps onto existing code

SimpleDictation already has the heavy machinery:

- System-wide CGEvent tap watching `leftMouseDown` — `ClipboardCycler.swift:30`
  (just add `leftMouseUp` to the mask).
- AX read of `kAXSelectedTextRangeAttribute` — `ClipboardCycler.swift:197`
  (add sibling `kAXSelectedTextAttribute`).
- Synthetic keypress + loop-guard marker — `postKey()` / `kSyntheticEventMarker`
  (`ClipboardCycler.swift:256`).
- Clipboard write + dedup history monitor — `StatusBarController.swift:745`.

Port ≈ 40–60 lines in `ClipboardCycler` + a menu toggle "Copy on select" (off by
default), mirroring the existing `onClipboardCyclingChanged` toggle.

Sources: `kouroshcodes/SelectCopy`; `tisfeng/SelectedTextKit`;
`yetone/get-selected-text`; PopClip forum (clipboard-on-activation thread).

---

> New voice/STT models are a separate feature tracked on branch
> `feature/dictation-engine-upgrades` (`docs/VOICE-MODELS.md`).
