# SimpleDictation Launch Plan ($4.20, one time)

Built by a 45-agent armada ensemble on 2026-07-08, same playbook as the MenuBarBuddy launch the same day. This is the master doc; details live in the sibling docs (DISTRIBUTION, LICENSING-PAYMENTS, BRAND-COPY, ASSETS-RUNBOOK, SYNTHESIS).

## The decision: direct web download. No Mac App Store. Ever.

Even more clear-cut than MenuBarBuddy. SimpleDictation has FOUR independent, code-verified App Store blockers, and every one of them is the product:

1. Text delivery is a synthetic Cmd+V keystroke posted to the HID event tap (SpeechManager.swift around 1038-1057). Sandboxed apps cannot inject input into other apps. Remove this and the app cannot type anywhere.
2. The clipboard-history cycler is a system-wide CGEvent tap that intercepts and rewrites your global Cmd+V (ClipboardCycler.swift). Impossible under the sandbox.
3. The hold-to-talk fn/option trigger uses a global event monitor (AppDelegate.swift around 223). Not available to sandboxed apps.
4. The external trigger file at ~/Library/Application Support/SimpleDictation/trigger is cross-app IPC outside any container by design.

The app ships with an empty entitlements dict and hardened runtime off on purpose. It is deliberately unsandboxed because that is the only way it can work. The $4.20-on-MAS price question is a secondary risk and not needed for the decision.

## The delicate part: it is already free at v1.3.0

The current DMG is free and public on GitHub Releases, and people use it daily. The riot-proof plan: grandfather v1.3.0 free forever, never pull it or nag it, and sell forward from a NEW v2.0.0. Take nothing away. In the v2 binary, a lightweight local heuristic marks returning users (detects their existing preferences on first run) as licensed, best effort, failing toward generosity. Never mint free license keys (there is no email list to verify against). A v1.3.0 user who never changed a setting simply keeps the free v1.3.0 or pays $4.20 for v2.

## The stack

- Payments: Lemon Squeezy at exactly $4.20 (merchant of record, absorbs VAT, license API), nets about $3.49.
- Delivery: Developer-ID-signed, notarized, stapled DMG on GitHub Releases. The current build.sh/build-dmg.sh do ZERO signing today (ad-hoc identity "-", hardened runtime off), so this is the #1 pre-ship engineering task.
- Updates: Sparkle 2 with an EdDSA-signed appcast (net-new, no Sparkle today).
- Licensing: offline-first Ed25519 token minted by a free Cloudflare Worker, stored in plain UserDefaults (no bundle-ID churn here, unlike MenuBarBuddy), verified locally on launch, fail-open. Gate only the paid engines and power features; Apple Speech, the hotkey, floating mic, and Enter stay ungated.
- Repo: stays PUBLIC, add a PolyForm Noncommercial 1.0.0 LICENSE (there is none today, so "open source" is not yet legally true). "Build it yourself" becomes the honest free tier.
- Site: site/index.html (single file). Target: GitHub Pages at https://cfranci.github.io/SimpleDictation, or the custom domain simpledictation.app if you register it.

## What exists right now

- site/index.html: complete landing page, orange/red mic-glow identity, animated hero, features, real screenshots, $4.20-vs-$15/mo pricing, privacy section, FAQ, full OG meta. Revised for the v2 paid launch (notarized, no Gatekeeper step, grandfather FAQ). Placeholders open: {BUY_URL} x4, {SUPPORT_EMAIL} x4.
- site/assets/: real captures from the live app on this Mac (macOS 26 Tahoe): menubar.png (the full engine menu, Status Ready), floating-mic.png (red mic mid-glow), typing.png (a dictated sentence in an isolated doc), og.png, poster.png, and the demo video.
- docs/: DISTRIBUTION, LICENSING-PAYMENTS (full Swift LicenseManager + Cloudflare Worker sketch), BRAND-COPY, ASSETS-RUNBOOK, SYNTHESIS, and this file.

## Go-live checklist (in order)

1. Apple Developer Program ($99/yr). Developer ID cert, notarytool creds. Add a release.sh that signs with Developer ID, flips hardened runtime ON, notarizes, staples. Keep ad-hoc in project.yml for local dev. First real notarytool submit is the only way to confirm WhisperKit's downloaded Core ML weights do not trip library validation (add the disable-library-validation entitlement if they do).
2. Commit a PolyForm Noncommercial LICENSE.
3. Build v2.0.0: bump MARKETING_VERSION, add Sparkle 2 as an SPM dep, bake the Ed25519 license public key and Sparkle keys via INFOPLIST_KEY_*.
4. Lemon Squeezy product at $4.20, 3 activations, no expiry. Cloudflare Worker /activate + /deactivate. Fill {BUY_URL}.
5. LicenseManager.swift + NSAlert activation UI (this app is AppKit, no SwiftUI) + "Buy SimpleDictation / Enter License" menu items. Add the local grandfather heuristic.
6. Pick the support inbox. Fill {SUPPORT_EMAIL}. Register simpledictation.app if you want it.
7. GitHub Pages on for /site, verify og.png renders in link previews.
8. Release v2.0.0 + Product Hunt + Show HN (lead with the four-blocker sandbox story and 100 percent on-device privacy) + r/macapps. Message every channel the same way: v1.3.0 is free forever, v2 is the maintained one at $4.20, or build it yourself.

## Open questions for Ga'noh

- Trial in the UI: no advertised trial (recommended, protects the "always free" story) vs a 14-day countdown in the menu. The degrade-to-free-tier enforcement code is harmless either way; this is only about whether to show a countdown.
- Confirm exactly $4.20 is selectable in Lemon Squeezy and its live fee on a $4.20 sale before copy hard-commits.
- License storage and the 3-activation seat cap: worth standing up the Cloudflare Worker for a $4.20 app, or ship honor-system offline keys only?
- Register simpledictation.app (about $15/yr) or stay on cfranci.github.io? The license Worker and OG copy assume the custom domain.
- Fix README step 4 ("gets typed out") to "gets pasted" so every surface agrees with the code before more copy derives from it.
