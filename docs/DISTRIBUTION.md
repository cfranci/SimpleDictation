# Distribution Strategy (Armada stitched output, 2026-07-08)

# Distribution Strategy: SimpleDictation

## FIRM RECOMMENDATION: DIRECT WEB DOWNLOAD ONLY

Ship a Developer-ID-signed, notarized, stapled DMG on GitHub Releases, sold through a Lemon Squeezy checkout at exactly $4.20, auto-updated via Sparkle 2. Keep the repo PUBLIC and add a PolyForm Noncommercial 1.0.0 LICENSE (there is none today). Ship the paid product as a NEW major version (v2.0.0) and leave the existing free v1.3.0 up forever. Skip the Mac App Store entirely.

This is not a close call, and the reason is technical and code-verified, not the price. I read the actual source. SimpleDictation's entire product is synthetic keystroke injection into other apps plus system-wide event taps, which is precisely the capability set the Mac App Store sandbox forbids. There is no "strip one feature and ship" path: remove the sandbox-blocked pieces and there is no app left.

---

## Why direct, not the Mac App Store: code-verified sandbox blockers

Unlike MenuBarBuddy (a single blocker), SimpleDictation has multiple independent MAS blockers and every one of them IS the product. Blockers 1 and 2 alone end the conversation.

### Blocker 1 — DEALBREAKER: the core function is synthetic Cmd+V keystroke injection into other apps

`SpeechManager.pasteText(_:)` (`SpeechManager.swift:1038-1057`) delivers transcribed text by setting `NSPasteboard.general`, then synthesizing a Command+V keystroke via raw `CGEvent(keyboardEventSource:)` posted to `.cghidEventTap`:

```
let cmdDown = CGEvent(keyboardEventSource: src, virtualKey: 55, keyDown: true)  // Command
cmdDown?.flags = .maskCommand
cmdDown?.post(tap: .cghidEventTap)
let vDown   = CGEvent(keyboardEventSource: src, virtualKey: 9,  keyDown: true)  // V
vDown?.post(tap: .cghidEventTap)
```

Important precision (the other distribution drafts got this wrong): this is NOT the Accessibility text API (`AXUIElementSetAttributeValue`). It is CGEvent posting to the HID event tap, which merely *requires* the Accessibility permission (checked via `AXIsProcessTrusted()`, `AppDelegate.swift:201`, and `AXIsProcessTrustedWithOptions`, line 205). Posting to `.cghidEventTap` is injecting input into OTHER applications. The App Sandbox has no entitlement that grants this; sandboxed apps are confined to their own event stream. Every delivery path does it: `pasteText` (1038-1057), the Enter/Return press (`virtualKey: 36`, lines 1018-1023, and `pressEnter()` around 1015), and the Whisper incremental backspace-and-repaste (`virtualKey: 51`, `SpeechManager.swift:707-710`). Take this away and the app cannot type. Nothing left to sell.

### Blocker 2 — the Cmd+V clipboard-history cycler is a system-wide event tap

`ClipboardCycler.swift:29-31` calls `CGEvent.tapCreate(tap: .cghidEventTap, place: .headInsertEventTap, ...)` and intercepts and suppresses the user's Cmd+V system-wide to implement history cycling (a headline README feature: "Hold Cmd, tap V to cycle"). A HID-level event tap that reads and rewrites the global keyboard stream is categorically impossible under the sandbox. (Note: this is `.cghidEventTap`, not a session-level tap; re-posting on line 256 is also `.cghidEventTap`. The cycler has a secondary insertion path via `AXUIElementSetAttributeValue` at lines 210/217, but that too is a non-sandboxable cross-app AX write.)

### Blocker 3 — the fn/option hotkey watches the global modifier stream

The hold-to-talk trigger uses `NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged)` (`AppDelegate.swift:223`) to detect fn/option system-wide whether or not SimpleDictation is focused. Global event monitoring is not available to sandboxed apps. Without it there is no "hold fn anywhere and talk," the app's entire interaction model. (`StatusBarController.swift:738` uses the same global-monitor mechanism for mouse events, so this is pervasive.)

### Blocker 4 — the external trigger file is cross-app IPC outside any container by design

`TriggerWatcher.swift:12` watches `~/Library/Application Support/SimpleDictation/trigger` via a `DispatchSource` file observer and reacts to writes from OTHER processes (doc comment, line 3: "e.g. from the AAA app"). Cross-app IPC through a shared file in `~/Library/Application Support` is exactly what the sandbox container walls off (a sandboxed app is confined to `~/Library/Containers/<bundleid>/`). Structurally incompatible with a container.

### Affirmative evidence the app is deliberately unsandboxed

`SimpleDictation.entitlements` is an empty `<dict/>` and `project.yml` sets `ENABLE_HARDENED_RUNTIME: NO`. The app is intentionally NOT sandboxed, the only way it can work. (A second `.entitlements` file exists on disk with full sandbox entitlements, but it lives inside the vendored WhisperKit example checkout at `build/SourcePackages/checkouts/WhisperKit/Examples/WhisperAX/WhisperAX/Resources/WhisperAX.entitlements`, is NOT referenced by project.yml, and is irrelevant. The active, project-referenced entitlements are the empty dict.)

### The $4.20 price is a SECONDARY risk — do NOT lead with it

Apple's post-March-2023 pricing added ~900 tiers at finer granularity, so whether exactly $4.20 is selectable in the US storefront is genuinely uncertain and may be selectable. Do NOT make a public "MAS can't do $4.20" claim, it is the weakest link and may be false. You do not need it: Blockers 1 and 2 already make MAS technically impossible. Direct sale charges exactly $4.20 with zero ambiguity, guaranteeing the meme/brand price off-store.

### Economics are a wash; MAS just costs you everything else

- MAS, Small Business Program (15%): Apple takes ~$0.63, you net ~$3.57.
- Lemon Squeezy (merchant of record, ~5% + ~$0.50/txn, absorbs VAT/sales tax): you net ~$3.49 AND get the buyer's email.

Per-unit money is roughly even at the SBP rate. MAS returns nothing the direct path does not, while costing price certainty, the buyer relationship, and the emergency-update path (Sparkle can ship a fix in hours; MAS review adds 24-48h). It also touches App Review guideline 1.1 subjectivity with the "$4.20 wink" copy. Verify LS's live fee at launch; provider terms drift.

---

## The hard, SimpleDictation-specific problem: it's ALREADY FREE at v1.3.0

The latest git tag is `v1.3.0` (verified) and its DMG is live on GitHub Releases; real users run it daily. Charging retroactively is a trust minefield and this is the one place the MenuBarBuddy playbook does NOT transfer. The riot-proof play:

**GRANDFATHER v1.3.0 permanently free, then sell forward from a NEW major version (v2.0.0). Take nothing away.**

- **v1.3.0 stays free, forever, untouched.** Never pull it, never brick it, never nag it. You literally cannot push code to an already-installed copy: v1.3.0 has no Sparkle (there is no `SUFeedURL` in the current build), so the absence of a nag is a free guarantee. This removes 100% of the "they took away my free app" anger, because you did not.
- **Ship the paid product as v2.0.0**, a clean major-version cutover that signals "new product line" far more clearly than v1.4.0. The paid line is "the maintained one that gets updates, notarized so it installs clean, auto-updating, with new engines." Do NOT invent a specific gated feature to justify the bump; "maintained + notarized + auto-updates" is honest and sufficient.
- **Feature-gate at the version boundary, never inside v1.3.0, and never degrade a v1.3.0 feature for licensed users.** Everything that shipped in v1.3.0 stays fully functional in v2 for buyers. New engines and future macOS-fix work land in the paid v2 line. Taking away what people already had generates justified backlash at any price.
- **The free/self-built build IS the trial.** A time-limited trial on an app that was fully free yesterday reads as a takeaway. The public source makes the pitch airtight: anyone can still build any version for free. Do NOT re-impose any trial clock on users upgrading from v1.3.0.
- **The message (identical in README, landing page, and launch posts):** "SimpleDictation has always been free and v1.3.0 always will be. v2 is the one I keep improving, notarized so it installs clean, auto-updating, with new engines. $4.20, one coffee, once, forever. Or keep the free one, no hard feelings."
- **Do NOT try to grandfather individual existing users with free keys.** There is no activation system or email list in v1.3.0, so you cannot verify who "existed." The clean answer is: v1.3.0 stays free, v2.0 is $4.20, build it yourself or pay.

---

## The GitHub repo: keep it PUBLIC, add a LICENSE first

**There is NO LICENSE file in the repo today** (verified). The README documents `./build.sh` from source, but with no license the code is "all rights reserved" by default, source-VISIBLE, not open-source. Technically nobody even has the legal right to build it for personal use, contradicting the README's own instructions. Fix before launch:

- **Keep the repo PUBLIC.** Auditable, cloud-free source IS the moat: "your voice never leaves your Mac, and you can read every line to prove it" is the whole privacy pitch against cloud-subscription rivals (Wispr Flow, superwhisper) and the direct counter to the Bartender trust scandal (secretly-added analytics). Going private throws that away and stops zero piracy (v1.3.0 is already cloned in the wild).
- **Add `LICENSE`: PolyForm Noncommercial 1.0.0** (same as MenuBarBuddy). Effect: anyone may read, audit, and build for personal use, but may NOT redistribute or resell. This (a) legally enables the honest "build it yourself / free version" path the README already promises, and (b) closes the fork-and-resell hole a permissive MIT would leave open. Add a `NOTICE.md`: v1.3.0 free forever, free if self-built, $4.20 for the notarized, auto-updating, supported build.
- **Open-core split.** Keep the paid machinery (Ed25519 license PUBLIC key baked into the binary, activation flow, Sparkle EdDSA signing keys, Developer-ID/notarization scripts) out of the public tree logic so the public repo still builds a fully functional, ad-hoc-signed, manually-installed FREE local build via `./build.sh`. Bake only the license PUBLIC key into the release build.
- **Piracy stance:** at $4.20 with a free v1.3.0 AND a "build it yourself" escape hatch, DRM is theater. Cloning + Xcode + XcodeGen + WhisperKit/Moonshine SPM resolution + build takes an afternoon; the paste-a-key path costs one coffee. You are selling convenience, notarization, auto-updates, new engines, and paying the developer, not preventing theft.

---

## Notarization, signing, and updates

### Switch build-dmg.sh from ad-hoc to Developer ID (the #1 ship blocker)

`build-dmg.sh` today runs xcodegen, builds Release, and packages a DMG, but `project.yml` sets `CODE_SIGN_IDENTITY: "-"` (ad-hoc) and `ENABLE_HARDENED_RUNTIME: NO`, and the script clears quarantine locally with `xattr -cr`. That is fine on the owner's own Mac but triggers Gatekeeper's "unidentified developer / cannot verify" wall for every downloader, a hard conversion killer for a paid app. (It is also why the existing free v1.3.0 warns on first launch; that is expected and left as-is, while v2.0 is properly notarized.) You need the Apple Developer Program ($99/yr), a "Developer ID Application" cert, Hardened Runtime ON, and notarization.

Add a `release.sh` (keep `build-dmg.sh` for local dev), setting the Developer ID identity and Hardened Runtime as xcodebuild overrides so local builds stay ad-hoc:

```bash
#!/bin/bash
set -e
APP_NAME="SimpleDictation"
VERSION="2.0.0"
DMG_NAME="${APP_NAME}-${VERSION}"
TEAM_ID="${APPLE_TEAM_ID:?set APPLE_TEAM_ID}"
SIGN_ID="Developer ID Application: ${DEVELOPER_NAME} (${TEAM_ID})"

xcodegen generate
xcodebuild -project ${APP_NAME}.xcodeproj -scheme ${APP_NAME} \
  -configuration Release -derivedDataPath build \
  CODE_SIGN_IDENTITY="${SIGN_ID}" CODE_SIGNING_REQUIRED=YES \
  ENABLE_HARDENED_RUNTIME=YES build

APP="build/Build/Products/Release/${APP_NAME}.app"

# --deep because WhisperKit + Moonshine bundle nested frameworks/dylibs that must ALL be signed,
# or notarization rejects unsigned nested code. (Or sign each embedded framework inside-out first.)
codesign --force --deep --options runtime --timestamp -s "${SIGN_ID}" "${APP}"
codesign --verify --deep --strict "${APP}"   # verify before submitting

rm -rf /tmp/${DMG_NAME}-dmg && mkdir -p /tmp/${DMG_NAME}-dmg
cp -R "${APP}" /tmp/${DMG_NAME}-dmg/
ln -s /Applications /tmp/${DMG_NAME}-dmg/Applications
rm -f ${DMG_NAME}.dmg
hdiutil create -volname "${APP_NAME}" -srcfolder /tmp/${DMG_NAME}-dmg -ov -format UDZO ${DMG_NAME}.dmg
rm -rf /tmp/${DMG_NAME}-dmg

codesign --force --timestamp -s "${SIGN_ID}" ${DMG_NAME}.dmg
xcrun notarytool submit ${DMG_NAME}.dmg --keychain-profile "SD-NOTARY" --wait
xcrun stapler staple ${DMG_NAME}.dmg
xcrun stapler validate ${DMG_NAME}.dmg
spctl -a -t open --context context:primary-signature ${DMG_NAME}.dmg
echo "==> ${DMG_NAME}.dmg is notarized and stapled."
```

Store creds once: `xcrun notarytool store-credentials SD-NOTARY --apple-id <id> --team-id <TEAMID> --password <app-specific-pw>`. Microphone/Speech usage strings are already present in project.yml.

### This app is EASIER to notarize than MenuBarBuddy

Unlike MenuBarBuddy, SimpleDictation never self-mutates its bundle, never mutates its bundle ID, and never re-signs at runtime, so none of MenuBarBuddy's two ship-blocking self-repair signing bugs exist here. Whisper model downloads write Core ML weights to `~/Library/Caches/` (`WhisperManager.swift:90`) and load them at runtime, which is normal for a Developer-ID app with Hardened Runtime. The empty entitlements dict is correct for the non-sandboxed case; enabling Hardened Runtime is purely mechanical (no JIT, no unsigned executable memory, no dyld injection, none of which the app uses). `NSEvent.addGlobalMonitorForEvents` and `CGEvent.tapCreate` keep working under Hardened Runtime without the sandbox as long as Accessibility is granted (which the app already prompts for).

### One open item to verify with a real submission

If notarization flags library validation when WhisperKit loads DOWNLOADED Core ML model weights under Hardened Runtime, you may need `com.apple.security.cs.disable-library-validation`. WhisperKit loads model *data*, not arbitrary dylibs, so standard Hardened Runtime should suffice, but confirm with an actual notarization run before launch. Mechanical fix, not a blocker.

### Updates: add Sparkle 2 (net-new; none in the tree today)

There is no Sparkle dependency and no appcast today. Add Sparkle 2 as a THIRD SPM package alongside WhisperKit and Moonshine:

```yaml
  Sparkle:
    url: https://github.com/sparkle-project/Sparkle.git
    from: "2.6.0"
```

- Add `- package: Sparkle` to the target dependencies.
- Generate an EdDSA key pair with Sparkle's `generate_keys`; store the private key in Keychain (off-repo); bake `SUPublicEDKey` into Info.plist via project.yml settings (it uses `GENERATE_INFOPLIST_FILE: YES`, so add `INFOPLIST_KEY_*` entries).
- Host an EdDSA-signed `appcast.xml` on GitHub Pages (`docs/appcast.xml` -> `https://cfranci.github.io/SimpleDictation/appcast.xml`); set `SUFeedURL`. Correct namespace: `http://www.andymatuschak.org/xml-namespaces/sparkle` (do NOT copy any template that fabricates a bogus namespace).
- Per release: `sign_update SimpleDictation-2.0.0.dmg`, paste the `edSignature` and byte count into a new `<item>` whose enclosure points at the GitHub Release asset. Sparkle 2 refuses unsigned enclosures, so `edSignature` is mandatory.
- Wire `SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)` in `applicationDidFinishLaunching`; add a "Check for Updates..." item to the status-bar menu (`StatusBarController.swift`); check on launch.

Why this matters especially here: the whole app rides on CGEventTap, global event monitoring, and Accessibility APIs Apple can change. The inevitable "macOS N broke the event tap / fn detection" fix reaches every paying user in a day, a latency MAS review would deny.

### License token storage: UserDefaults, not Keychain

The bundle ID is stable (`com.simpledictation.app`, no runtime mutation), so unlike MenuBarBuddy there is no bundle-ID churn and no migration chain to worry about. Store the Ed25519-signed token in `UserDefaults.standard` (key `SimpleDictation.licenseToken`) where all the app's other prefs already live (engine, hotkey, mic size, incremental mode) — consistency, no migration machinery; verify it offline against the embedded public key on every launch.

### Refunds

Direct = you own the policy. At $4.20, with a free v1.3.0 AND a "build it yourself" escape, refund abuse is a non-issue. Offer a no-questions refund in the FAQ; it costs almost nothing and builds trust.

---

## Competitive position

| Product | Price | Distribution | Voice leaves the Mac? | Source |
|---|---|---|---|---|
| Wispr Flow | ~$12-15/mo | Direct | Cloud-processed | Closed |
| superwhisper | ~$8.49/mo or ~$249 lifetime | Direct | Local-capable | Closed |
| MacWhisper | ~$32-59 one-time | Direct | Local | Closed |
| VoiceInk | ~$19-29 one-time | Direct | Local | Open (MIT) |
| Apple Dictation | Free | Built-in | Online-biased | Closed |
| **SimpleDictation** | **$4.20 one-time** | **Direct (notarized DMG)** | **Never. 100% on-device, works offline** | **Source-available (PolyForm NC)** |

The 10-engine claim is accurate and verified (README table lists Apple Speech + 8 Whisper/Distil-Whisper variants + Moonshine Tiny = 10). One-liner: "Wispr Flow is $15 every month and your voice goes to the cloud. SimpleDictation is $4.20 once, 10 local engines, your voice never leaves your Mac, and you can read the source to prove it. One coffee, forever." Keep the price at exactly $4.20 everywhere; the meme only works if it is consistent, and people screenshot "$4.20." Never discount.

---

## LAUNCH CHECKLIST (sequenced)

### Phase 0 — Legal & identity (do FIRST; blocks everything)
- [ ] Enroll in the Apple Developer Program ($99/yr); record the Team ID.
- [ ] Create a "Developer ID Application" certificate; install it in the login keychain.
- [ ] Store notarization creds: `xcrun notarytool store-credentials SD-NOTARY --apple-id <id> --team-id <TEAMID> --password <app-specific-pw>`.
- [ ] Add `LICENSE` (PolyForm Noncommercial 1.0.0) + `NOTICE.md` (open-core: v1.3.0 free forever, free if self-built, $4.20 for the notarized build). Commit and push before any announcement. Fixes the current all-rights-reserved state and legally grants the free-build path the README already promises.

### Phase 1 — Build the sellable artifact (as v2.0.0)
- [ ] Bump `MARKETING_VERSION` to `2.0.0` in project.yml (clean major-version cutover signals the paid line).
- [ ] Set Developer ID + `ENABLE_HARDENED_RUNTIME: YES` as xcodebuild overrides in release.sh; keep project.yml's ad-hoc `CODE_SIGN_IDENTITY: "-"` for local dev.
- [ ] Add `release.sh` (xcodegen -> Release build -> `codesign --force --deep --options runtime --timestamp` -> DMG -> notarize -> staple -> `stapler validate` -> spctl). Keep build-dmg.sh for local dev.
- [ ] Add Sparkle 2 as the third SPM package + target dependency; generate EdDSA keys; bake `SUPublicEDKey` + `SUFeedURL` into Info.plist; add `SPUStandardUpdaterController` + "Check for Updates..." menu item.
- [ ] Bake the Ed25519 license PUBLIC key into the release build; keep activation/validation logic out of the public tree so the public tree still builds a working free binary.
- [ ] Verify: `codesign --verify --deep --strict`, `xcrun stapler validate`, `spctl -a -t open --context context:primary-signature SimpleDictation-2.0.0.dmg`.

### Phase 2 — Payment, updates, distribution plumbing
- [ ] Lemon Squeezy: product at exactly $4.20 USD, one-time; License Keys on; activation limit 3 (laptop + desktop + work), no expiry. Capture API key + webhook secret (chmod 600 / Keychain). Confirm live LS fee/exact-price support.
- [ ] Add `LicenseManager.swift` (CryptoKit Ed25519, UserDefaults key `SimpleDictation.licenseToken`, offline-first) + activation UI (AppKit NSAlert/NSPanel: "Buy SimpleDictation... / Enter License..." menu items). "Buy" opens the LS checkout in the default browser. Consider a thin Cloudflare Worker to sign the offline token if LS's key API doesn't do Ed25519 natively.
- [ ] Host `docs/appcast.xml` on GitHub Pages; point the enclosure at the GitHub Release asset; EdDSA-sign each DMG.
- [ ] Stand up the landing page (GitHub Pages `docs/`; custom domain e.g. simpledictation.app optional, adds credibility proportional to the price).
- [ ] Rewrite README Download section: v2.0.0 (paid, notarized) front and center, with a visible "v1.3.0 is still free, forever" line linking the old release, plus the documented "build it yourself" path (a feature, not a leak).

### Phase 3 — Grandfather / transition guardrails (SimpleDictation-specific, do NOT skip)
- [ ] Leave the v1.3.0 GitHub Release LIVE and untouched; label it "Legacy: free version." Do not pull it, do not brick it, do not add a nag, do not add a trial to v2 for former free users.
- [ ] Draft the transition message ("always free, v1.3.0 always will be, v2 is the maintained one, $4.20 or keep the free one") and use it verbatim in README, landing page, release notes, and launch posts. Consistency prevents backlash.

### Phase 4 — Release automation (optional but recommended)
- [ ] GitHub Actions `release.yml`, tag-triggered (`v2.*`): checkout -> import Developer ID cert from base64 secret -> xcodegen + Release build -> DMG -> notarize -> staple -> `softprops/action-gh-release` -> regenerate + commit `appcast.xml`.
- [ ] Repo secrets: `DEVELOPER_ID_CERT` (base64 .p12), `DEVELOPER_ID_CERT_PASSWORD`, `NOTARY_PASSWORD`. Never commit the Ed25519 license private key, Sparkle private key, or LS API key.

### Phase 5 — Fresh-Mac verification (acceptance gate, before any announcement)
- [ ] On a Mac that NEVER built the app: download the v2 DMG, drag to /Applications, launch, confirm NO Gatekeeper warning (proves notarization/stapling).
- [ ] Grant Microphone + Accessibility + Speech Recognition; confirm hold-fn-talk-release types into TextEdit AND a Chrome text input (exercises the CGEvent `.cghidEventTap` injection path), double-tap presses Enter, Cmd+V clipboard cycling works (exercises the `CGEvent.tapCreate` head-inserted tap), and a Whisper model downloads then switches over.
- [ ] Trigger file IPC: `echo "start $(date +%s)" > ~/Library/Application\ Support/SimpleDictation/trigger` then `echo "stop $(date +%s)" > ...` (append a nonce so identical commands register as distinct writes); confirm the app responds.
- [ ] License activation happy path + offline case with a real key; deactivate and confirm the seat frees.
- [ ] Sparkle end-to-end: publish a test 2.0.1 to the appcast, confirm an installed 2.0.0 copy sees and self-installs the update.

### Phase 6 — Launch (simultaneous)
- [ ] GitHub Release v2.0.0 with the notarized DMG; release notes lead with the privacy/on-device story + new engines.
- [ ] Product Hunt (tagline from brand-copy), scheduled ~00:01 PT.
- [ ] Hacker News "Show HN: SimpleDictation — $4.20 local voice-to-text, 10 on-device engines, your voice never leaves your Mac (source-available)."
- [ ] r/macapps + r/macOS (typing-demo GIF), MacRumors software forum, AlternativeTo (vs Wispr Flow / superwhisper on price + privacy), MacUpdate.
- [ ] Twitter/X thread (typing demo + "$15/mo cloud dictation vs $4.20 once, on-device").
- [ ] Email tip lines: MacStories, 9to5Mac, Cult of Mac (privacy-vs-subscription hook).

### Phase 7 — Post-launch
- [ ] Support = GitHub Issues + a forwarding email (support@simpledictation.app). No ticket system at this price/volume.
- [ ] Monitor license-activation failure rate (near zero; a spike means the Worker has a bug), refund rate (target near zero), and Sparkle adoption.
- [ ] Watch macOS point releases + WhisperKit releases that touch CGEventTap / global event monitoring / Accessibility (the app's whole mechanism). Re-test on each beta; keep a fast Sparkle push and rollback (previous appcast item) ready.
- [ ] MAS is NOT a v2 consideration and effectively never will be: keystroke injection + system-wide taps + cross-app trigger file cannot be sandboxed. Do not revisit.

---

## FINAL RECOMMENDATION (one line)

Ship DIRECT ONLY, a Developer-ID-signed / notarized / stapled DMG on a $4.20 Lemon Squeezy checkout with Sparkle 2 auto-updates, released as a NEW v2.0.0 while the already-public v1.3.0 stays free forever (grandfather, take nothing away), repo kept PUBLIC and relicensed PolyForm Noncommercial as open-core, and skip the Mac App Store entirely, because the app's core is synthetic Cmd+V keystroke injection (`CGEvent` posting to `.cghidEventTap`) plus system-wide event taps and a cross-app trigger file, all structurally impossible in the MAS sandbox, and this app is actually EASIER to notarize than MenuBarBuddy since it never self-mutates its bundle.

## Open questions
- Is exactly $4.20 selectable on the US storefront under Apple's granular pricing? Does NOT change the recommendation (Blockers 1 and 2 kill MAS independent of price), but do not make a public 'MAS can't do $4.20' claim without checking.
- Does notarization flag library validation when WhisperKit loads DOWNLOADED Core ML model weights under Hardened Runtime? WhisperKit loads model data (not arbitrary dylibs) so standard Hardened Runtime should suffice, but confirm with a real notarytool submission; if flagged, add com.apple.security.cs.disable-library-validation. Mechanical fix, resolve before launch, not a blocker.
- Does Lemon Squeezy's license-key API support an Ed25519 offline-validation flow, or does it need a thin Cloudflare Worker to sign the token? Load-bearing for the 'no phone-home, works offline' claim central to this app's privacy pitch (owned by the licensing-payments section).
- Confirm the owner is fine leaving v1.3.0 free forever alongside the paid v2. Strong recommendation is yes (costs nothing, defuses the entire backlash risk); if the goal is to fully retire the free tier, the transition gets riskier and needs a softer message.