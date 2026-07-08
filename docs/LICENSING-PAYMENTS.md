# Licensing and Payments (Armada stitched output, 2026-07-08)

# SimpleDictation — Licensing & Payments

Grounded in the real source (verified this pass). SimpleDictation is a pure-**AppKit** `NSApplicationDelegate` menu-bar agent: `NSApp.setActivationPolicy(.accessory)` at **AppDelegate.swift:219** (no Dock icon), macOS 14+, XcodeGen + two SwiftPM deps (`WhisperKit`, `Moonshine`/`MoonshineVoice` at project.yml:9-26). It is **not sandboxed** — `SimpleDictation.entitlements` is literally `<dict/>`. Its whole job depends on Accessibility: text is typed via synthetic `CGEvent` Cmd+V, Enter is a synthetic `CGEvent`, the clipboard cycler installs a low-level `CGEventTap` (`ClipboardCycler`), and an external trigger file lives at `~/Library/Application Support/SimpleDictation/trigger` (`TriggerWatcher.swift:12`). There is **no SwiftUI anywhere** and **no Settings/Preferences window** — every option is an inline `NSMenuItem` built in `StatusBarController.setupMenu()` (line 158); the menu ends with a separator at **347**, `Restart` at **349**, `Quit` at **353**. The app is **already free** — `MARKETING_VERSION: 1.3.0` (project.yml:38) ships as a public GitHub Releases DMG right now.

The licensing layer must: (a) never block the menu bar or the login-time hotkey, (b) be pure AppKit (NSAlert/NSPanel, not SwiftUI), (c) not disturb `.accessory` or the fragile event-tap machinery, and (d) never brick dictation for a paying user.

**The single biggest simplification vs the MenuBarBuddy playbook:** SimpleDictation has a **stable bundle ID** (`com.simpledictation.app`, project.yml:30) and **no self-repair / bundle-ID bumping**. MenuBarBuddy's entire "store the token on the migration chain, never Keychain" reasoning was a workaround for a *churning identity* and **does not apply here**. This app uses plain `UserDefaults` with zero migration plumbing, and that is safe because the token is Ed25519-signed.

---

## 1. Payment provider: Lemon Squeezy

Same conclusion as MenuBarBuddy, and it holds for the same three reasons: exact free-form **$4.20** price, true **merchant of record** (they file EU/UK VAT + US sales tax), and a first-class **license-key API** (activate / validate / deactivate). For a solo dev selling a sub-$5 utility internationally, MoR is the entire value: the alternative is personally owing sales tax in dozens of jurisdictions on one-coffee sales.

| Requirement | Lemon Squeezy | Gumroad | Paddle | Stripe Payment Links |
|---|---|---|---|---|
| Exact **$4.20** price | Yes, free-form | Yes | Low-price friction reported* | Yes |
| **Merchant of Record** (files your VAT/GST/sales tax) | **Yes** | Yes | Yes | **No — you owe global VAT** |
| **License-key API** (activate/validate/deactivate) | **Yes, first-class** | Thin/absent | Add-on, heavier | **None — build it yourself** |
| Effective take on $4.20 | ~5% + $0.50 ≈ $0.71* | ~10% flat* | ~5% + $0.50* | 2.9% + $0.30, no MoR/keys |

*\*Verify current terms at launch; provider fees and low-price minimums change. Directionally right.*

**Net ≈ $3.49/sale** after LS's cut — the price of never touching a VAT return.

**One challenge unique to a $4.20 price:** per-transaction floors and MoR fees eat a large *percentage*. Fine and expected (the meme price is the brand, not the margin), but it means **do not add a second per-sale fee anywhere in the stack.** That is why the license-minting Worker below runs on **Cloudflare's free tier** and why there is **no per-launch phone-home** — every avoidable cost per sale matters more at $4.20 than at $20.

**Provider config:** product at **$4.20** one-time; License Keys **on**, **activation limit = 3** (desktop / laptop / work Mac), **no expiry**; post-purchase page + receipt carry the license key **and** a link to the **notarized GitHub Release DMG** (§7). Keep the **LS API key** and the **Ed25519 private key** off the public repo (§9).

---

## 2. The "already free in the wild" transition (the delicate part)

v1.3.0 is a free public DMG on GitHub Releases **right now**. A cold "14-day trial then degrade" applied to the *current* feature set would be a bait-and-switch on existing users. My firm recommendation: **grandfather the free version, sell forward, degrade-never-brick.**

- **v1.3.0 and earlier stay free forever.** They already exist in the wild; you cannot and should not un-ship them. Do not time-bomb old builds or push a "pay now or it stops" notification. Existing users keep everything.
- **The paid product is v2.0+**, an honest version bump. Release note: *"v1.3.0 is the last free version. v2.0 adds [Sparkle auto-update, newer engines, X] and is $4.20 one-time. v1.3.0 remains free forever."*
- **Grandfather returning free users on first run of the paid binary.** If v2.0 detects markers a fresh install would not have, treat that user as **licensed forever, no nag, ever.** This is the single most important anti-riot line of code.
- **New installs of v2.0+ get a genuinely generous 14-day trial** — *because the free 1.x DMG is one GitHub tag away.* A stingy trial is pointless when the old free build is a click away; it would just route people back to it. So 14 days fully functional, then **degrade, never brick.**
- **The build-from-source path is the honest, stated free tier.** Anyone with Xcode + the deps can build the full app. At $4.20 the toolchain friction exceeds the price. **Add a PolyForm Noncommercial license to the repo** so this path is actually *legally granted* — a public repo with no license grants no rights, so the license turns "build it yourself" from an unlicensed leak into a real free tier. Say this plainly in the README and FAQ.

### Grandfather heuristic — grounded in the real keys (corrected)

The opus attempt keyed partly off `dictationEngine`, but the source shows `dictationEngine` **defaults to `"apple"` and is only written on set** (AppDelegate.swift:31-32) — a returning user who never changed engines would not have it. Use the keys that are **actually written to disk on real use** instead:

- `enabledModifiers` — array, written whenever the user toggles a modifier (AppDelegate.swift:27) and by `StatusBarController.toggleModifier`.
- `incrementalMode` — bool, written on toggle (AppDelegate.swift:120).
- `clipboardCyclingEnabled` — bool, read at AppDelegate.swift:327.
- `floatingMicSize` — Int, written by `setMicSize` (StatusBarController.swift:560).
- `dictationLocale` — string, written on locale change.

Presence of **any** of these means a prior install already ran and persisted a real preference. It is still best-effort (a brand-new v1.3.0 user who launched once and touched nothing has none of them) — so pair it with the version-bump note and lean on the generous trial as the safety net. Honesty over cleverness: flagged as a heuristic on purpose.

---

## 3. License architecture: offline-first, Ed25519-signed

The app must be usable instantly with no network (it runs 100% locally, and it launches at login before the network may be up). So the license verifies **offline** after a one-time online activation:

```
Buy on LS -> user gets an LS LICENSE KEY (used once to claim a seat)
   -> paste into "Enter License…" (a plain AppKit NSAlert with an input field)
   -> app POSTs the key to a $0 Cloudflare Worker, which activates it against
      the LS API server-side and returns a fresh Ed25519-SIGNED, self-contained TOKEN
      (the LS instance_id is embedded in the token — see §3.1)
   -> token stored in UserDefaults.standard under one key
   -> app verifies it LOCALLY on every launch with the embedded PUBLIC key.
      Never needs the network again (unless the user deactivates a seat).
```

**Two-token design:** the LS key proves purchase and claims one of the 3 seats (used once). The **signed token** is what the app trusts day-to-day, verified offline forever.

**Private key never in the app.** It lives only as a Cloudflare Worker secret. The app ships only the **public** verify key (safe to commit). Since the repo is **public**, embedding the private key would let anyone mint infinite licenses. The public key is safe to read and still cannot forge a signature.

**Token format:** `SD1-<base32url(payload)>.<base32url(signature)>` where payload is compact JSON `{ v, kid, sku, email, order, iid }`. `kid` (key id) lets you rotate the signing key in a future version without invalidating old tokens. Sign Ed25519 over the **raw base32-decoded payload bytes**, never a re-`JSONEncoder().encode(...)` at verify time — JSON key ordering is not byte-stable across sign/verify, a bug that bit MenuBarBuddy. Verify with CryptoKit `Curve25519.Signing`.

### 3.1 Fix the deactivate gap all four attempts missed

For "Deactivate this Mac" to actually free the LS seat, the app must know the **LS instance_id** that activation returned. LS's activate response returns an `instance.id`; the Worker must embed it in the token as `iid`. On deactivate, the app reads `iid` from its own token and passes it back; the Worker calls LS `/deactivate` with `license_key` + `instance_id`. Without this, self-serve transfer silently no-ops. (Alternative if you would rather keep the token minimal: persist `instance_id` in a separate `UserDefaults` key at activation time. Embedding it in the signed token is cleaner — it travels with the license and cannot be edited without breaking the signature.)

### 3.2 Storage: `UserDefaults.standard`, one key, no Keychain

- The token is Ed25519-signed, so tampering breaks the signature; it is a signed *entitlement*, not a secret credential. There is nothing for Keychain to protect. Keychain would only add code and edge cases.
- **The MenuBarBuddy `migrateFromOldBundleID` step does not exist here and must be dropped** — the bundle ID never changes, so `UserDefaults.standard.set(token, forKey: "SimpleDictation.licenseToken")` just persists. Cleanest divergence from the playbook.
- **A second, sharper reason to avoid Keychain, specific to this ship:** the app moves from **ad-hoc signing** (`CODE_SIGN_IDENTITY: "-"`) to **Developer ID** for the paid release (§7). Keychain items whose ACL was written under the ad-hoc identity can fail to read silently under the new signing identity. UserDefaults survives an identity change without drama. (Real effect, but it depends on how items were added — treat it as a supporting reason, not the load-bearing one.)
- UserDefaults also survives Migration Assistant and Time Machine restore (`~/Library/Preferences/com.simpledictation.app.plist`), matching every other setting the app already stores.
- Optional second home: since `~/Library/Application Support/SimpleDictation/` already exists (the trigger file), a plaintext `license.token` there is a fine backup if you ever want to survive a `defaults delete`. Ship v1 with UserDefaults only; do not overthink anti-tamper at $4.20.

---

## 4. Anti-abuse stance (deliberately light, proportional to $4.20)

Source is public; DRM is theater. Enforcement surface = **verify the signature offline + cap at 3 seats server-side via the LS activation limit**. No obfuscation, no debugger checks, no per-launch phone-home, no online re-validation, **no hardware fingerprinting** (brittle, resented, pointless against a public tree). A **"Deactivate this Mac"** action calls the Worker's `/deactivate` (which calls LS deactivate with the embedded `iid`, §3.1), then clears the local token, so users self-serve transfers.

**Fail OPEN, never closed:** if a token is present but the embedded public key fails to load (a build bug), assume **licensed**, not trial — a paying user must never be locked out by our bug, and this app is accessibility-adjacent ("types for you"). Cracking costs a `git clone` and a compile; buying costs one paste. Most people will paste.

---

## 5. Swift implementation (pure AppKit, CryptoKit only, no new runtime deps)

### `LicenseManager.swift`

```swift
import Foundation
import CryptoKit
import Combine

enum LicenseState: Equatable {
    case licensed(email: String)     // paid OR grandfathered
    case trial(daysLeft: Int)
    case expired
}

final class LicenseManager: ObservableObject {
    static let shared = LicenseManager()

    // Safe to commit — PUBLIC verify key only. Private key lives in the Worker secret.
    private static let publicKeyB64 = "REPLACE_WITH_BASE64_ED25519_PUBLIC_KEY"
    private static let activateURL   = URL(string: "https://license.simpledictation.app/activate")!
    private static let deactivateURL = URL(string: "https://license.simpledictation.app/deactivate")!
    private let trialDays = 14

    // Plain UserDefaults keys — no migration chain (stable bundle ID).
    private let tokenKey       = "SimpleDictation.licenseToken"
    private let firstRunKey    = "SimpleDictation.trialFirstRun"
    private let maxDaysKey     = "SimpleDictation.trialMaxDays"
    private let grandfatherKey = "SimpleDictation.grandfathered"

    @Published private(set) var state: LicenseState = .expired
    private let defaults = UserDefaults.standard
    private init() { detectGrandfather(); refresh() }

    // Pre-2.0 users of the FREE version are licensed forever. Keys chosen because
    // they are WRITTEN on real use (dictationEngine is NOT — it defaults to "apple"
    // and is only persisted on change, so it is deliberately excluded here).
    private func detectGrandfather() {
        if defaults.bool(forKey: grandfatherKey) { return }
        let returning =
            defaults.array(forKey: "enabledModifiers")       != nil ||
            defaults.object(forKey: "incrementalMode")       != nil ||
            defaults.object(forKey: "clipboardCyclingEnabled") != nil ||
            defaults.object(forKey: "floatingMicSize")       != nil ||
            defaults.string(forKey: "dictationLocale")       != nil
        if returning { defaults.set(true, forKey: grandfatherKey) }
    }

    func refresh() {                                  // pure-local; never blocks the menu bar
        if defaults.bool(forKey: grandfatherKey) { state = .licensed(email: "early supporter"); return }
        if let t = defaults.string(forKey: tokenKey), let c = verify(token: t) {
            state = .licensed(email: c.email); return
        }
        if let t = defaults.string(forKey: tokenKey), publicKeyMissing(), !t.isEmpty {
            state = .licensed(email: ""); return       // FAIL OPEN on build fault
        }
        state = trialState()
    }

    var isLicensed: Bool { if case .licensed = state { return true }; return false }
    var isUsable:   Bool { if case .expired  = state { return false }; return true }   // gates paid tier

    func activate(key: String) async -> Result<Void, LicenseError> {
        var req = URLRequest(url: Self.activateURL); req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONEncoder().encode(
            ["license_key": key.trimmingCharacters(in: .whitespacesAndNewlines),
             "instance": deviceName()])
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else { return .failure(.serverRejected) }
            let token = (try? JSONDecoder().decode([String: String].self, from: data))?["token"] ?? ""
            guard verify(token: token) != nil else { return .failure(.badToken) }
            defaults.set(token, forKey: tokenKey)
            await MainActor.run { self.refresh() }
            return .success(())
        } catch { return .failure(.network) }
    }

    func deactivate() async {                          // frees the LS seat via embedded iid, clears token
        guard let token = defaults.string(forKey: tokenKey) else { return }
        var req = URLRequest(url: Self.deactivateURL); req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONEncoder().encode(["token": token])
        _ = try? await URLSession.shared.data(for: req)
        defaults.removeObject(forKey: tokenKey)
        await MainActor.run { self.refresh() }
    }

    struct Claim: Codable { let v: Int; let kid: String; let sku: String
                            let email: String; let order: String; let iid: String }
    private func publicKeyMissing() -> Bool { Data(base64Encoded: Self.publicKeyB64) == nil }

    private func verify(token: String) -> Claim? {
        guard token.hasPrefix("SD1-") else { return nil }
        let p = token.dropFirst(4).split(separator: ".")
        guard p.count == 2,
              let payload = Base32.decode(String(p[0])),         // raw bytes we signed
              let sig     = Base32.decode(String(p[1])),
              let pkData  = Data(base64Encoded: Self.publicKeyB64),
              let pub     = try? Curve25519.Signing.PublicKey(rawRepresentation: pkData),
              pub.isValidSignature(sig, for: payload),           // verify over EXACT bytes
              let c = try? JSONDecoder().decode(Claim.self, from: payload),
              c.sku == "simpledictation"
        else { return nil }
        return c
    }

    private func trialState() -> LicenseState {
        if defaults.object(forKey: firstRunKey) == nil { defaults.set(Date(), forKey: firstRunKey) }
        let first   = defaults.object(forKey: firstRunKey) as? Date ?? Date()
        let elapsed = max(0, Calendar.current.dateComponents([.day], from: first, to: Date()).day ?? 0)
        let seen    = max(elapsed, defaults.integer(forKey: maxDaysKey))   // soft clock-rollback guard
        defaults.set(seen, forKey: maxDaysKey)
        let left = trialDays - seen
        return left > 0 ? .trial(daysLeft: left) : .expired
    }

    private func deviceName() -> String { Host.current().localizedName ?? "Mac" }
    enum LicenseError: Error { case network, serverRejected, badToken }
}
```

`Base32` is a ~30-line Crockford codec (`Base32.swift`; case-insensitive + URL-safe so pasted tokens survive case-normalizing UIs). **No `migrateFromOldBundleID` to touch — that whole step is deleted.**

### Activation UI — pure AppKit `NSAlert`

The app has **no Settings window** and **no SwiftUI**, so do the simplest correct thing: an `NSAlert` with an accessory `NSTextField`. This **sidesteps the entire `.accessory` ↔ `.regular` activation-policy dance** that a real `NSWindow` would force (no visible Dock-icon flash, no `windowWillClose` restore to get wrong). Add to `StatusBarController`:

```swift
@objc func enterLicense() {
    let alert = NSAlert()
    alert.messageText = "Enter your SimpleDictation license"
    alert.informativeText = "Paste the license key from your Lemon Squeezy receipt."
    alert.addButton(withTitle: "Activate")
    alert.addButton(withTitle: "Buy — $4.20")
    alert.addButton(withTitle: "Cancel")

    let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
    field.placeholderString = "XXXX-XXXX-XXXX-XXXX"
    field.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
    alert.accessoryView = field

    NSApp.activate(ignoringOtherApps: true)          // .accessory apps must self-activate
    switch alert.runModal() {
    case .alertFirstButtonReturn:
        let key = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        Task {
            let result = await LicenseManager.shared.activate(key: key)
            await MainActor.run {
                let done = NSAlert()
                if case .success = result {
                    done.messageText = "Thanks — SimpleDictation is licensed."
                } else {
                    done.messageText = "That key didn't activate."
                    done.informativeText = "Check the key, your connection, or that you have activations left (3 Macs)."
                }
                NSApp.activate(ignoringOtherApps: true); done.runModal()
            }
        }
    case .alertSecondButtonReturn: buySimpleDictation()
    default: break
    }
}

@objc func buySimpleDictation() {
    NSWorkspace.shared.open(URL(string: "https://simpledictation.lemonsqueezy.com/buy/YOUR-VARIANT")!)
}

@objc func deactivateLicense() {
    let a = NSAlert()
    a.messageText = "Deactivate this Mac?"
    a.informativeText = "Frees one of your 3 seats so you can activate on another Mac. Re-activate any time with the same key."
    a.addButton(withTitle: "Deactivate"); a.addButton(withTitle: "Cancel")
    NSApp.activate(ignoringOtherApps: true)
    guard a.runModal() == .alertFirstButtonReturn else { return }
    Task { await LicenseManager.shared.deactivate() }
}
```

Because it is an `NSAlert`, there is **no window ivar, no `setActivationPolicy` dance, no close-restore** — the app stays `.accessory` throughout. (If you later want a richer state-driven license window, the app already has an `NSPanel` precedent in `AppDelegate.showModelNotification` at line 341+; not needed for v1.)

### Menu integration in `StatusBarController.setupMenu()`

Insert license items **just before the separator at line 347** (before the `Restart`/`Quit` block at 349/353). `setupMenu()` rebuilds fresh on each open, so state re-reads live — no Combine subscription strictly required (subscribe once to `$state` and rebuild only if you want instant updates while the menu is open).

```swift
// after the last feature item, before the separator at line 347:
menu.addItem(NSMenuItem.separator())
switch LicenseManager.shared.state {
case .licensed(let email):
    let li = NSMenuItem(title: email == "early supporter"
        ? "Licensed (early supporter — thank you)"
        : (email.isEmpty ? "Licensed" : "Licensed to \(email)"),
        action: nil, keyEquivalent: "")
    li.isEnabled = false; menu.addItem(li)
    let deact = NSMenuItem(title: "Deactivate this Mac…", action: #selector(deactivateLicense), keyEquivalent: "")
    deact.target = self; menu.addItem(deact)
case .trial(let daysLeft):
    if daysLeft <= 3 {
        let buy = NSMenuItem(title: "Buy SimpleDictation — \(daysLeft) day\(daysLeft == 1 ? "" : "s") left ($4.20)",
                             action: #selector(buySimpleDictation), keyEquivalent: "")
        buy.target = self; menu.addItem(buy)
    }
    let enter = NSMenuItem(title: "Enter License…", action: #selector(enterLicense), keyEquivalent: "")
    enter.target = self; menu.addItem(enter)
case .expired:
    let buy = NSMenuItem(title: "Buy SimpleDictation ($4.20)", action: #selector(buySimpleDictation), keyEquivalent: "")
    buy.target = self; menu.addItem(buy)
    let enter = NSMenuItem(title: "Enter License…", action: #selector(enterLicense), keyEquivalent: "")
    enter.target = self; menu.addItem(enter)
}
```

The nag budget is exactly this: one menu item in the final 3 days. **Never a modal** — this app is used mid-typing into Slack/other apps; a stolen-focus dialog during dictation would be sabotage.

### Paid-tier gating — CORRECTED to the real `setEngine` (switches on `sender.tag`)

The judges caught a real bug in a sibling attempt: it read `sender.representedObject as? String`, but the actual `setEngine` (StatusBarController.swift:446-473) switches on **`sender.tag`** — case **601 = "apple"** (free), **602-610 = Whisper/Moonshine** (paid). That representedObject code would never match and would ship broken. Gate on the tag instead:

```swift
@objc private func setEngine(_ sender: NSMenuItem) {
    let isPaidEngine = sender.tag != 601            // 601 = Apple Speech (always free)
    if isPaidEngine, !LicenseManager.shared.isUsable {   // expired AND not grandfathered
        buySimpleDictation(); return
    }
    switch sender.tag {                              // ...existing 601–610 mapping unchanged...
    case 601: currentEngine = "apple"
    // 602–610 as-is
    default: break
    }
    onEngineChanged?(currentEngine)
}
```

Apply the same `isUsable` guard to clipboard-history cycling (`ClipboardCycler.cycle()` — early-return if not usable) and incremental mode. **`isUsable` is true during trial, when licensed, and when grandfathered**, so nothing changes for anyone until a *new* user's trial expires.

**On expiry, degrade — never disable.** Core hold-to-talk with **Apple Speech (tag 601), the hotkey, the floating mic, and synthetic Enter injection are NEVER gated.** The gate is only the paid Whisper/Moonshine engines (fall back to Apple Speech), clipboard cycling, and incremental mode — roughly the value 1.3.0 did *not* give away. Gating auto-updates is deliberately avoided: it just strands expired users on old, unpatched models and is a thin value story next to the engines.

---

## 6. Cloudflare Worker: activation backend (~50 lines, $0)

```javascript
// Secrets: LS_API_KEY, ED25519_PRIVATE_KEY_B64.  Deploy: wrangler deploy
export default {
  async fetch(req, env) {
    const url = new URL(req.url);

    if (req.method === 'POST' && url.pathname === '/activate') {
      const { license_key, instance } = await req.json();
      const ls = await fetch('https://api.lemonsqueezy.com/v1/licenses/activate', {
        method: 'POST',
        headers: { 'Authorization': `Bearer ${env.LS_API_KEY}`,
                   'Content-Type': 'application/json', 'Accept': 'application/json' },
        body: JSON.stringify({ license_key, instance_name: instance }),
      });
      if (!ls.ok) return Response.json({ message: 'Invalid or already-used key.' }, { status: 422 });
      const d = await ls.json();
      const email = d.meta?.customer_email ?? '';
      const order = String(d.meta?.order_id ?? '');
      const iid   = String(d.instance?.id ?? '');           // <-- embed for /deactivate (§3.1)

      const payload = JSON.stringify({ v: 1, kid: 'sd-2026-07', sku: 'simpledictation', email, order, iid });
      const bytes = new TextEncoder().encode(payload);
      const key = await crypto.subtle.importKey(
        'raw', base32Decode(env.ED25519_PRIVATE_KEY_B64), { name: 'Ed25519' }, false, ['sign']);
      const sig = await crypto.subtle.sign('Ed25519', key, bytes);  // WebCrypto Ed25519 — NO jose/JWT
      return Response.json({ token: `SD1-${base32Encode(bytes)}.${base32Encode(new Uint8Array(sig))}` });
    }

    if (req.method === 'POST' && url.pathname === '/deactivate') {
      const { token } = await req.json();
      const iid = /* parse SD1- token, base32-decode payload, read .iid */ '';
      await fetch('https://api.lemonsqueezy.com/v1/licenses/deactivate', {
        method: 'POST',
        headers: { 'Authorization': `Bearer ${env.LS_API_KEY}`,
                   'Content-Type': 'application/json', 'Accept': 'application/json' },
        body: JSON.stringify({ license_key: /* stored/looked-up */ '', instance_id: iid }),
      });
      return Response.json({ ok: true });
    }
    return new Response('Not found', { status: 404 });
  }
};
```

Sign over **raw payload bytes** (never re-serialized JSON) so it matches Swift verification byte-for-byte. Use WebCrypto `crypto.subtle.sign('Ed25519', ...)` directly — **do not pull in jose/JWT**, which is a red herring for a raw-Ed25519 flow. Host at `license.simpledictation.app` (free Workers custom domain).

---

## 7. Delivery: notarized DMG on GitHub Releases (the #1 pre-ship blocker)

**`build-dmg.sh` does ZERO code signing today.** It runs only `xattr -cr` (line 28) to strip quarantine locally, then `hdiutil create … UDZO` (line 35). There is no `codesign` call anywhere, and project.yml has `CODE_SIGN_IDENTITY: "-"` (41) + `ENABLE_HARDENED_RUNTIME: NO` (45). A **paying customer** who downloads that DMG hits Gatekeeper's "cannot verify the developer" wall and bounces. This is the single blocker before the first sale.

Fix requires a real **Developer ID Application** cert (**Apple Developer Program, $99/yr**) + hardened runtime + notarization + stapling. Two project.yml changes:
- `ENABLE_HARDENED_RUNTIME: NO` → **`YES`** (notarization requires it).
- `CODE_SIGN_IDENTITY: "-"` → your **Developer ID Application** identity.

Because WhisperKit + Moonshine bundle frameworks under `@executable_path/../Frameworks` (`LD_RUNPATH_SEARCH_PATHS`, project.yml:44), you must sign **`--deep`** so the embedded frameworks are covered before signing the outer app, or notarization rejects the artifact.

Keep `build-dmg.sh` for local free builds; add a separate `release.sh` for shipping:

```bash
APP="build/Build/Products/Release/SimpleDictation.app"
codesign --force --deep --options runtime --timestamp \
  -s "Developer ID Application: <Your Name> (TEAMID)" "$APP"
# Do NOT run `xattr -cr` on a shipped build — that line is for local dev only.
# On an already-Developer-ID-signed build, xattr -cr strips the attrs Gatekeeper
# needs and breaks stapling.
# build the DMG (hdiutil ... UDZO), then notarize + staple the DMG itself:
xcrun notarytool submit "${DMG_NAME}.dmg" --keychain-profile "SD-NOTARY" --wait
xcrun stapler staple "${DMG_NAME}.dmg"
gh release create "v${VERSION}" "${DMG_NAME}.dmg" \
  --title "SimpleDictation ${VERSION}" --notes "First paid release."
```

**Entitlements note:** the app is not sandboxed and stays that way; hardened runtime does **not** require the sandbox. The empty `<dict/>` entitlements are fine to notarize as-is. Do **not** add a mic/audio-input entitlement expecting it to fix Accessibility — Accessibility is a TCC permission, not an entitlement, and adding sandbox-style device entitlements to a non-sandboxed hardened-runtime app is unnecessary. If a specific hardened-runtime exception is ever needed (it is not for CGEvent/Accessibility), add it explicitly; ship with the empty entitlements first and verify the notarized build still requests Accessibility normally.

**One artifact, verified two ways:** the notarized DMG on the GitHub Release is the LS post-purchase link **and** the Sparkle enclosure (§8). Since the repo is public, gating the *download* buys nothing — what you sell is the **signed token** that unlocks the paid tier plus the convenience of a notarized, auto-updating binary.

---

## 8. Sparkle 2 auto-update (EdDSA appcast on GitHub Pages)

No auto-updater exists today (README says `git pull && ./build.sh`). Add **Sparkle 2** as the **third SwiftPM dep** alongside WhisperKit + Moonshine:

```yaml
packages:
  Sparkle:
    url: https://github.com/sparkle-project/Sparkle.git
    from: "2.6.0"
# add `- package: Sparkle` under the target's dependencies
```

Generate keys with `Sparkle/bin/generate_keys`; the **public** EdDSA key goes into Info.plist, the private key stays off-repo. **Because project.yml uses `GENERATE_INFOPLIST_FILE: YES` (line 34) with no manual plist**, wire the two keys via `INFOPLIST_KEY_*` build settings (or switch to a checked-in plist):

```yaml
INFOPLIST_KEY_SUFeedURL: "https://cfranci.github.io/SimpleDictation/appcast.xml"
INFOPLIST_KEY_SUPublicEDKey: "YOUR_SPARKLE_PUBLIC_EDDSA_KEY"
```

Wire the updater in `applicationDidFinishLaunching`:

```swift
import Sparkle
private lazy var updaterController = SPUStandardUpdaterController(
    startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
_ = updaterController   // force init; starts the background check
```

Add a `Check for Updates…` menu item near the top of `setupMenu()`. Since the app is `.accessory`, Sparkle's own update UI must self-activate — call `NSApp.activate(ignoringOtherApps:)` before presenting it, same as the license alert. Each release: `Sparkle/bin/sign_update SimpleDictation-2.0.0.dmg`, paste `sparkle:edSignature` + byte `length` into a new top `<item>` in `appcast.xml` whose `enclosure url` is the GitHub Release DMG. **Sparkle 2 refuses unsigned enclosures**, so `edSignature` is mandatory. Serve `appcast.xml` free from `docs/` via GitHub Pages.

---

## 9. Secrets checklist (public repo)

- **Safe to commit:** Ed25519 license **public** key, Sparkle **public** EdDSA key, `SUFeedURL`, LS checkout URL, all Swift source, PolyForm NC `LICENSE`.
- **NEVER commit:** Ed25519 license **private** key (Worker secret only), Sparkle **private** EdDSA key (keep in 1Password), LS **API key** (Worker secret), notarization creds / `SD-NOTARY` keychain profile, Developer ID `.p12`.

---

## 10. Launch checklist

1. Apple Developer Program ($99/yr) → Developer ID Application cert.
2. LS product at **$4.20**, License Keys on, **3** activations, no expiry; confirm live fee/terms.
3. Cloudflare Worker (free tier): `/activate` (validate against LS, embed `instance_id` as `iid`, mint Ed25519-signed token) and `/deactivate` (read `iid` from token, call LS deactivate); LS API key + Ed25519 **private** key as Worker secrets; custom domain `license.simpledictation.app`.
4. Generate Ed25519 keypair offline. Private → Worker. Public (base64 raw 32 bytes) → `LicenseManager.publicKeyB64`.
5. Add `LicenseManager.swift` + `Base32.swift`. **(No `migrateFromOldBundleID` — this app has none.)**
6. Add `enterLicense()` / `buySimpleDictation()` / `deactivateLicense()` to `StatusBarController`; insert license items before the separator at line 347; **gate paid engines by `sender.tag != 601` + `isUsable`**, plus clipboard cycling and incremental mode; leave Apple Speech (601) / hotkey / floating mic / Enter ungated.
7. Ship the corrected grandfather heuristic (keys: `enabledModifiers` / `incrementalMode` / `clipboardCyclingEnabled` / `floatingMicSize` / `dictationLocale`) so pre-2.0 free users are licensed forever, no nag.
8. Add PolyForm Noncommercial `LICENSE` to the repo; README/FAQ: "build from source = free tier; v1.3.0 stays free forever."
9. `project.yml`: `ENABLE_HARDENED_RUNTIME: YES`, `CODE_SIGN_IDENTITY` = Developer ID; add Sparkle SwiftPM dep + `INFOPLIST_KEY_SUFeedURL` / `INFOPLIST_KEY_SUPublicEDKey`.
10. `release.sh`: Developer ID `--deep --options runtime --timestamp` codesign → DMG → `notarytool submit --wait` → `stapler staple`; do **not** `xattr -cr` a shipped build.
11. GitHub Release v2.0.0 with the notarized DMG; GitHub Pages `appcast.xml` with `edSignature` + `length`.
12. LS post-purchase page + receipt email link to the Release DMG directly.
13. Smoke test: buy a test key → paste into the `NSAlert` → confirm token via `defaults read com.simpledictation.app SimpleDictation.licenseToken` → quit + relaunch **offline**, still licensed → flip a fresh Mac's clock past 14 days, confirm degrade-not-brick (Apple Speech still types, Whisper items route to buy) → confirm a pre-2.0 upgrade user is auto-grandfathered → **"Deactivate this Mac" actually frees the seat in the LS dashboard** (proves the `iid` round-trip) → confirm Sparkle finds the update from a v1.9.x test build.

## Summary

Lemon Squeezy sells at exactly **$4.20** as merchant of record, issues keys, and links to a **notarized DMG on GitHub Releases** — which requires **replacing today's zero-codesign pipeline** (`build-dmg.sh` runs only `xattr -cr` + `hdiutil`; project.yml has `CODE_SIGN_IDENTITY:"-"`, `ENABLE_HARDENED_RUNTIME: NO`) with a real Developer ID cert + hardened runtime + `codesign --deep` + notarize + staple, the single pre-ship blocker. Keys activate once against a **$0 Cloudflare Worker** (raw-Ed25519 via WebCrypto, no jose) that embeds the LS `instance_id` and returns an **offline-verifiable signed token** stored in **plain `UserDefaults`** — the big divergence from MenuBarBuddy, whose migration-chain/Keychain reasoning does not apply (stable bundle ID); UserDefaults is additionally safer across the ad-hoc→Developer-ID identity change. Activation UI is a **pure AppKit `NSAlert`** (no SwiftUI, no Settings window, no activation-policy dance). The trial is rethought for an app **already free in the wild**: **grandfather pre-2.0 free users forever** (via keys that are actually written on use, not the `"apple"`-defaulted `dictationEngine`), add a **PolyForm NC license** so build-from-source is a real free tier, and give new users a **generous 14-day degrade-never-brick trial** that gates only the paid engines/clipboard-cycling/incremental — **gated on `sender.tag != 601`, correcting a broken `representedObject` snippet** — while Apple Speech hold-to-talk stays free forever. The self-serve **"Deactivate this Mac"** works because the token carries the LS `instance_id`, closing a gap every source attempt glossed over. Anti-abuse is deliberately light (3 server seats, fail-open, no fingerprinting) because the source is public and the price is the deterrent. Sparkle 2 (third SwiftPM dep, keys wired via `INFOPLIST_KEY_*` since the app uses `GENERATE_INFOPLIST_FILE`) keeps everyone current via an EdDSA-signed appcast on GitHub Pages, pointing at the same notarized DMG.

## Open questions
- LS activate response shape: confirm the exact JSON path for instance.id and customer_email against the current Lemon Squeezy license API before wiring the Worker (fields have shifted historically).
- Confirm the notarized, hardened-runtime build still triggers the Accessibility permission prompt normally with the empty <dict/> entitlements — verify on a clean Mac before the first paid release, since hardened runtime occasionally interacts with TCC prompts.
- Decide whether to embed instance_id in the signed token (chosen here) vs. persisting it in a separate UserDefaults key — the token approach is cleaner but means the deactivate route must base32-decode and parse the token server-side, and the license_key needed for LS deactivate must be recoverable (store it in KV keyed by order at activation, or include it in the token).
- Whether to make the repo private at v2.0 or keep it public under PolyForm NC — kept-public-with-PolyForm is recommended here (honest free tier, no Sparkle/CI disruption), but this is a business call for Ga'noh.