# SimpleDictation Launch Plan ($4.20, one time)

> **Current status.** The ordered launch steps are [GO_LIVE.md](GO_LIVE.md). Payments are the Stripe Payment Link in `site/buy.html`, fulfilled by the Worker. Lemon Squeezy is not used. Sparkle is not shipped and this launch does not add it. The DMG is not notarized yet (`notarize-dmg.sh` is the command that does it). Price stays $4.20 once, the trial is 14 days, a key covers two Macs, and v1.3.0 users are grandfathered. The list below is the July 2026 plan. Where it disagrees with GO_LIVE.md, GO_LIVE.md wins.

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

- Payments: Stripe Payment Link at exactly $4.20, one time. The Worker mints the key. See GO_LIVE.md. (The July plan below this file's status note said Lemon Squeezy. That was not what shipped.)
- Delivery: Developer-ID-signed, notarized, stapled DMG on GitHub Releases. `notarize-dmg.sh` does that signing. `build-dmg.sh` is still ad-hoc. The published DMG is not notarized until GO_LIVE.md step 4 is run.
- Updates: no Sparkle. Buyers download a new DMG. Do not add Sparkle for this launch.
- Licensing: offline-first Ed25519 token minted by a free Cloudflare Worker, stored in plain UserDefaults (no bundle-ID churn here, unlike MenuBarBuddy), verified locally on launch, fail-open. Gate only the paid engines and power features; Apple Speech, the hotkey, floating mic, and Enter stay ungated.
- Repo: stays PUBLIC, add a PolyForm Noncommercial 1.0.0 LICENSE (there is none today, so "open source" is not yet legally true). "Build it yourself" becomes the honest free tier.
- Site: site/index.html (single file). Target: GitHub Pages at https://cfranci.github.io/SimpleDictation, or the custom domain simpledictation.app if you register it.

## What exists right now

- site/index.html: complete landing page, orange/red mic-glow identity, animated hero, features, real screenshots, $4.20-vs-$15/mo pricing, privacy section, FAQ, full OG meta. Revised for the v2 paid launch (notarized, no Gatekeeper step, grandfather FAQ). Placeholders open: {BUY_URL} x4, {SUPPORT_EMAIL} x4.
- site/assets/: real captures from the live app on this Mac (macOS 26 Tahoe): menubar.png (the full engine menu, Status Ready), floating-mic.png (red mic mid-glow), typing.png (a dictated sentence in an isolated doc), og.png, poster.png, and the demo video.
- docs/: DISTRIBUTION, LICENSING-PAYMENTS (full Swift LicenseManager + Cloudflare Worker sketch), BRAND-COPY, ASSETS-RUNBOOK, SYNTHESIS, and this file.

## Go-live checklist (in order)

Use [GO_LIVE.md](GO_LIVE.md). Do not follow the July checklist that used to live here (Lemon Squeezy, Sparkle, a v2.0.0 version bump, three activation seats). The shipped product is version 1.4.0, Stripe, two Macs, a 14-day trial, and no auto-updater.

## Open questions for Ga'noh

- Trial in the UI: no advertised trial (recommended, protects the "always free" story) vs a 14-day countdown in the menu. The degrade-to-free-tier enforcement code is harmless either way; this is only about whether to show a countdown.
- Confirm the live Stripe Payment Link is $4.20 one time (GO_LIVE.md). Lemon Squeezy is not the provider.
- License storage and the 3-activation seat cap: worth standing up the Cloudflare Worker for a $4.20 app, or ship honor-system offline keys only?
- Register simpledictation.app (about $15/yr) or stay on cfranci.github.io? The license Worker and OG copy assume the custom domain.
- Fix README step 4 ("gets typed out") to "gets pasted" so every surface agrees with the code before more copy derives from it.
