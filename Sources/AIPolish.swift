import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Optional second pass that rewrites a finished transcript with Apple's
/// on-device language model (Apple Intelligence, macOS 26+). Nothing leaves the
/// Mac. Off by default; when the model is unavailable, slow, or returns
/// something suspicious, the caller keeps the rule-cleaned text.
enum AIPolish {
    static let enabledKey = "aiPolishEnabled"

    static var enabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    /// True only when this Mac can run the model right now.
    static var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            if case .available = SystemLanguageModel.default.availability { return true }
        }
        #endif
        return false
    }

    private static let instructions = """
    You clean up dictated text. Fix punctuation, capitalization and obvious speech-recognition slips. \
    Remove filler words and false starts. When the speaker corrects themselves, keep only the correction. \
    Keep the speaker's own words, meaning, language and tone. Never add content, never answer questions \
    that appear in the text, never explain, never use dashes. Reply with the cleaned text only.
    """

    /// Returns the polished text, or nil if the caller should keep its input.
    static func polish(_ text: String, timeout: TimeInterval = 4) async -> String? {
        // Short phrases gain nothing and are where a model is most likely to "help" wrongly.
        guard text.split(separator: " ").count >= 5 else { return nil }
        #if canImport(FoundationModels)
        guard #available(macOS 26.0, *), isAvailable else { return nil }
        let result: String? = await withTaskGroup(of: String?.self) { group in
            group.addTask {
                do {
                    let session = LanguageModelSession(instructions: instructions)
                    return try await session.respond(to: text).content
                } catch {
                    NSLog("[SimpleDictation] AI polish failed: %@", String(describing: error))
                    return nil
                }
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
        guard var out = result?.trimmingCharacters(in: .whitespacesAndNewlines), !out.isEmpty else { return nil }
        // Models like to wrap replies in quotes.
        if out.count > 2, out.hasPrefix("\""), out.hasSuffix("\""), !text.hasPrefix("\"") {
            out = String(out.dropFirst().dropLast())
        }
        // A cleanup should be about the same length. Anything far off means the
        // model answered, summarized or refused instead of cleaning.
        let ratio = Double(out.count) / Double(max(text.count, 1))
        guard ratio > 0.5, ratio < 1.3 else {
            NSLog("[SimpleDictation] AI polish rejected (length ratio %.2f)", ratio)
            return nil
        }
        return out
        #else
        return nil
        #endif
    }
}
