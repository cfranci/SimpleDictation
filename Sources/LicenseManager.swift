// Sources/LicenseManager.swift
// SimpleDictation v2.0 license layer. One-time online redemption, then pure-local
// Ed25519 verification forever after. Fail-open on a build fault; degrade, never brick.

import Foundation
import CryptoKit
import Combine
import IOKit

enum LicenseState: Equatable {
    case licensed(email: String)   // paid, Reddit key, or grandfathered pre-2.0 user
    case trial(daysLeft: Int)      // generous 14-day window for a fresh v2 install
    case expired                   // trial elapsed -> Apple Speech only, never bricked
}

enum LicenseError: LocalizedError {
    case network
    case serverRejected(String)
    case badToken
    case alreadyActivated

    var errorDescription: String? {
        switch self {
        case .network:           return "Could not reach the activation server. Check your connection and try again. The app keeps working in the meantime."
        case .serverRejected(let m): return m.isEmpty ? "That code was not accepted. Check for typos (codes look like SD42-XXXX-XXXX-XXXX)." : m
        case .badToken:          return "Activation could not be verified. Please try again, or email chaseefrancis1@gmail.com."
        case .alreadyActivated:  return "That code is already used up. Each code activates once. Grab another from the thread, or buy for $4.20."
        }
    }
}

final class LicenseManager: ObservableObject {
    static let shared = LicenseManager()

    // MARK: Config
    // Safe to commit: PUBLIC verify key only. Fill after running scripts/gen-keys.mjs.
    // The PRIVATE key lives ONLY as a Cloudflare Worker secret; this repo is public.
    private static let publicKeyB64 = "g0917Ql8Kfp6mEGt5k23rlbTdLrmyyQ4iiOdOJK3of0="
    // Worker base URL on the API KING account. Update if you bind a custom domain.
    static let workerBaseURL = "https://simpledictation-licenses.api-king.workers.dev"
    // Stripe Payment Link (live, from buy.html).
    static let buyURL = URL(string: "https://buy.stripe.com/4gMdR987h9mtchK2sCg360q")!
    static let supportEmail = "chaseefrancis1@gmail.com"

    private let trialDays = 14

    // MARK: UserDefaults keys (domain com.simpledictation.app, no migration chain)
    private let tokenKey       = "SimpleDictation.licenseToken"
    private let emailKey       = "SimpleDictation.licenseEmail"
    private let firstRunKey    = "SimpleDictation.trialFirstRun"
    private let maxDaysKey     = "SimpleDictation.trialMaxDays"
    private let grandfatherKey = "SimpleDictation.grandfathered"
    private let deviceIDKey    = "SimpleDictation.deviceID"
    private let defaults = UserDefaults.standard

    @Published private(set) var state: LicenseState = .expired

    private init() {
        detectGrandfather()
        refresh()
    }

    // MARK: Public surface used by the gates + menu

    /// True when premium features are allowed: licensed, grandfathered, OR still in trial.
    /// Only `.expired` is false. This is the ONE gate the rest of the app calls.
    var isUsable: Bool { if case .expired = state { return false }; return true }

    /// True only for a genuinely paid/grandfathered user (menu wording).
    var isLicensed: Bool { if case .licensed = state { return true }; return false }

    /// The feature gate. `tag` is the NSMenuItem tag from setEngine.
    /// 601 = Apple Speech is ALWAYS free. Everything else is premium.
    func isPremiumEngine(tag: Int) -> Bool { tag != 601 }

    // MARK: Grandfather — pre-2.0 free users are licensed forever, no nag ever.
    //
    // Uses only keys WRITTEN on real v1.x use. dictationEngine is EXCLUDED: it defaults
    // to "apple" and is only persisted on change (AppDelegate.swift:31-32), so a returning
    // user who never switched engines would not have it. These five are written by real use:
    //   enabledModifiers        (AppDelegate.swift:27, toggleModifier)
    //   incrementalMode         (AppDelegate.swift:120)
    //   clipboardCyclingEnabled (read AppDelegate.swift:327; written by toggle)
    //   floatingMicSize         (StatusBarController.swift:560, setIconSize)
    //   dictationLocale         (StatusBarController.swift:442, selectLanguage)
    private func detectGrandfather() {
        guard !defaults.bool(forKey: grandfatherKey) else { return }
        let returning =
            defaults.array(forKey:  "enabledModifiers")        != nil ||
            defaults.object(forKey: "incrementalMode")         != nil ||
            defaults.object(forKey: "clipboardCyclingEnabled") != nil ||
            defaults.object(forKey: "floatingMicSize")         != nil ||
            defaults.string(forKey: "dictationLocale")         != nil
        if returning { defaults.set(true, forKey: grandfatherKey) }
    }

    // MARK: Refresh (pure-local, never touches the network)

    func refresh() {
        // 1. Grandfathered pre-2.0 free user -> licensed forever, no nag.
        if defaults.bool(forKey: grandfatherKey) {
            state = .licensed(email: "early supporter"); return
        }
        // 2. Stored token present: verify Ed25519 locally.
        if let token = defaults.string(forKey: tokenKey), !token.isEmpty {
            if let claim = verifyToken(token) {
                let email = claim.email.isEmpty ? (defaults.string(forKey: emailKey) ?? "") : claim.email
                state = .licensed(email: email); return
            }
            // 3. FAIL OPEN only if the embedded PUBLIC KEY itself won't parse (our build bug).
            //    A paying user must never be locked out by our mistake.
            if publicKeyLoadFailed() {
                state = .licensed(email: ""); return
            }
            // Signature genuinely invalid (tamper / corrupt). FAIL CLOSED: drop it, fall to trial.
            defaults.removeObject(forKey: tokenKey)
        }
        // 4. Otherwise: trial or expired.
        state = trialState()
    }

    // MARK: Verification (CryptoKit, offline, over EXACT signed bytes)

    // Must match the token payload the Worker signs EXACTLY (gen-keys.mjs payloadBytesFor):
    // { v, kid, sku, email, order, iid } with order == iid == the short code for self-issued keys.
    // Any missing field makes JSONDecoder throw keyNotFound and every token would be rejected.
    struct Claim: Decodable {
        let v: Int; let kid: String; let sku: String
        let email: String; let order: String; let iid: String
    }

    private func publicKeyLoadFailed() -> Bool {
        guard let raw = Data(base64Encoded: Self.publicKeyB64) else { return true }
        return (try? Curve25519.Signing.PublicKey(rawRepresentation: raw)) == nil
    }

    private func verifyToken(_ token: String) -> Claim? {
        guard token.hasPrefix("SD1-") else { return nil }
        let parts = token.dropFirst(4).split(separator: ".", maxSplits: 1)
        guard parts.count == 2,
              let payload = Base32.decode(String(parts[0])),   // the raw bytes we signed
              let sig     = Base32.decode(String(parts[1])),
              let pkRaw   = Data(base64Encoded: Self.publicKeyB64),
              let pub     = try? Curve25519.Signing.PublicKey(rawRepresentation: pkRaw),
              pub.isValidSignature(sig, for: payload),         // verify over exact bytes
              let claim   = try? JSONDecoder().decode(Claim.self, from: payload),
              claim.v == 1, claim.sku == "simpledictation"
        else { return nil }
        return claim
    }

    // MARK: Trial (soft clock-rollback guard; degrade never brick)

    private func trialState() -> LicenseState {
        if defaults.object(forKey: firstRunKey) == nil {
            defaults.set(Date(), forKey: firstRunKey)
        }
        let first   = defaults.object(forKey: firstRunKey) as? Date ?? Date()
        let elapsed = max(0, Calendar.current.dateComponents([.day], from: first, to: Date()).day ?? 0)
        let seen    = max(elapsed, defaults.integer(forKey: maxDaysKey))  // never goes backward
        defaults.set(seen, forKey: maxDaysKey)
        let left = trialDays - seen
        return left > 0 ? .trial(daysLeft: left) : .expired
    }
    // Note: the trial is honor-system by design. `defaults delete com.simpledictation.app`
    // resets it and the D1 cap is dedupe not DRM — acceptable at $4.20 where price, not
    // enforcement, is the deterrent (SYNTHESIS.md).

    // MARK: Activate (the ONE online call, single time)

    func activate(code rawCode: String, email userEmail: String = "") async -> Result<Void, LicenseError> {
        // Accept dashes/spaces/any case; the Worker normalizes server-side too.
        let code = rawCode.uppercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted).joined()
        guard !code.isEmpty else { return .failure(.serverRejected("Enter a license code.")) }
        guard let url = URL(string: "\(Self.workerBaseURL)/v1/activate") else { return .failure(.network) }

        struct Body: Encodable { let code: String; let device_id: String; let email: String }
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONEncoder().encode(Body(code: code, device_id: deviceID(), email: userEmail))

        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
            struct R: Decodable { let token: String?; let email: String?; let error: String? }
            let decoded = (try? JSONDecoder().decode(R.self, from: data)) ?? R(token: nil, email: nil, error: nil)

            switch status {
            case 200:
                guard let token = decoded.token, !token.isEmpty else { return .failure(.badToken) }
                // Only trust a token that verifies locally with our embedded public key.
                guard let claim = verifyToken(token) else { return .failure(.badToken) }
                defaults.set(token, forKey: tokenKey)
                // Store licenseEmail for the menu label (server echo, then claim, then typed).
                let stored = firstNonEmpty(decoded.email, claim.email, userEmail)
                defaults.set(stored, forKey: emailKey)
                await MainActor.run { self.refresh() }   // @Published fires -> menu self-heals
                return .success(())
            case 409:
                return .failure(.alreadyActivated)
            case 403, 404, 410, 422:
                return .failure(.serverRejected(decoded.error ?? ""))
            default:
                return .failure(.network)
            }
        } catch {
            return .failure(.network)
        }
    }

    // MARK: Device id — stable per-Mac dedupe handle for the D1 activation cap.
    // IOPlatformUUID (stable across reboots/OS updates); persisted-UUID fallback.
    // Not a fingerprint, not a secret; sent only in the activation call.

    private func deviceID() -> String {
        if let cached = defaults.string(forKey: deviceIDKey), !cached.isEmpty { return cached }
        var id = UUID().uuidString
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        if service != 0 {
            if let uuid = IORegistryEntryCreateCFProperty(service, "IOPlatformUUID" as CFString,
                              kCFAllocatorDefault, 0)?.takeRetainedValue() as? String, !uuid.isEmpty {
                id = uuid
            }
            IOObjectRelease(service)
        }
        defaults.set(id, forKey: deviceIDKey)
        return id
    }

    // First non-empty of the candidates, else "".
    private func firstNonEmpty(_ candidates: String?...) -> String {
        for c in candidates { if let c = c, !c.isEmpty { return c } }
        return ""
    }
}
