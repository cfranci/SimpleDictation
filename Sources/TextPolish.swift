import Foundation

/// One custom-dictionary row. `heard` is what the speech engine tends to write;
/// `write` is what should be typed instead. An empty `heard` makes the row
/// vocabulary-only: it never rewrites text, it just biases engines toward `write`.
struct DictionaryEntry: Codable, Identifiable, Equatable {
    var id = UUID()
    var heard: String
    var write: String
}

/// The custom dictionary plus rule-based cleanup. Runs entirely on-device and
/// synchronously, on every transcript, before it is typed or shown as a caption.
/// (The optional language-model pass lives in AIPolish.)
enum TextPolish {
    static let dictionaryKey = "customDictionary"
    static let cleanupKey = "smartCleanupEnabled"

    private static let lock = NSLock()
    private static var cached: [DictionaryEntry]?

    // MARK: Settings

    static var entries: [DictionaryEntry] {
        get {
            lock.lock(); defer { lock.unlock() }
            if let c = cached { return c }
            var loaded: [DictionaryEntry] = []
            if let data = UserDefaults.standard.data(forKey: dictionaryKey),
               let decoded = try? JSONDecoder().decode([DictionaryEntry].self, from: data) {
                loaded = decoded
            }
            cached = loaded
            return loaded
        }
        set {
            lock.lock(); cached = newValue; lock.unlock()
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: dictionaryKey)
            }
        }
    }

    /// On by default: every paid competitor removes fillers out of the box.
    static var cleanupEnabled: Bool {
        get { UserDefaults.standard.object(forKey: cleanupKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: cleanupKey) }
    }

    /// Names and terms to bias the engines toward (Apple Speech contextual
    /// strings, Whistle keywords). Deduplicated, in the user's order.
    static var vocabulary: [String] {
        var seen = Set<String>()
        var out: [String] = []
        for e in entries {
            let w = e.write.trimmingCharacters(in: .whitespacesAndNewlines)
            if !w.isEmpty, seen.insert(w.lowercased()).inserted { out.append(w) }
        }
        return out
    }

    // MARK: Pipeline

    /// Cleanup, then dictionary. Idempotent: applying it to its own output
    /// changes nothing, because several call sites clean the same text twice.
    static func apply(_ text: String) -> String {
        let lang = String((UserDefaults.standard.string(forKey: "dictationLocale") ?? "en-US").prefix(2))
        return apply(text, entries: entries, cleanup: cleanupEnabled, language: lang)
    }

    static func apply(_ text: String, entries: [DictionaryEntry], cleanup: Bool, language: String) -> String {
        var s = text
        if cleanup { s = self.cleanup(s, language: language) }
        s = applyDictionary(s, entries: entries)
        return s
    }

    // MARK: Cleanup

    /// Words people stutter on. Deliberately excludes doubles that are often
    /// meant ("that that", "had had", "very very", "no no").
    private static let stutterWords =
        "i|the|a|an|and|to|we|it|so|but|of|in|my|is|if|or|for|on|at|with|this|they|he|she"

    static func cleanup(_ text: String, language: String) -> String {
        var s = text
        let startedUpper = s.unicodeScalars.first.map { CharacterSet.uppercaseLetters.contains($0) } ?? false

        // Filler and stutter rules are English-only: "um" is a real word in
        // Portuguese, and the stutter list is English function words.
        if language == "en" {
            // "scratch that" discards the sentence spoken so far.
            s = replace(s, "[^.!?\\n]*\\bscratch that\\b[,.!]?\\s*", " ")
            // um, uh, uhm, erm, hmm (with a trailing comma if there is one).
            s = replace(s, "\\b(?:u+m+|u+h+m*|e+r+m+|h+m+m+)\\b,?\\s*", "")
            // "the the" -> "the", "I I I" -> "I".
            s = replace(s, "\\b(\(stutterWords))(?:\\s+\\1\\b)+", "$1")
        }

        // Tidy what the removals leave behind. Safe in every language.
        s = replace(s, "[ \\t]+([,.!?;:])", "$1")        // no space before punctuation
        s = replace(s, ",\\s*([.!?])", "$1")              // ", ." -> "."
        s = replace(s, "[ \\t]{2,}", " ")
        s = replace(s, "^[,;:\\s]+", "")
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)

        // If a removed filler was carrying the sentence's capital, restore it.
        if startedUpper, let first = s.first, first.isLowercase {
            s = first.uppercased() + s.dropFirst()
        }
        return s
    }

    private static func replace(_ s: String, _ pattern: String, _ template: String) -> String {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return s }
        return re.stringByReplacingMatches(in: s, options: [], range: NSRange(s.startIndex..., in: s), withTemplate: template)
    }

    // MARK: Dictionary

    static func applyDictionary(_ text: String, entries: [DictionaryEntry]) -> String {
        var s = text
        for e in entries {
            let heard = e.heard.trimmingCharacters(in: .whitespacesAndNewlines)
            let write = e.write.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !heard.isEmpty, !write.isEmpty, heard != write else { continue }
            // Whole words only, so "art" never rewrites the middle of "start".
            let pattern = "(?<![\\p{L}\\p{N}])" + NSRegularExpression.escapedPattern(for: heard) + "(?![\\p{L}\\p{N}])"
            guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let matches = re.matches(in: s, options: [], range: NSRange(s.startIndex..., in: s))
            // Where `heard` sits inside `write` ("francis" in "Chase Francis"):
            // a match already surrounded by the full `write` must be left alone,
            // or a second pass would produce "Chase Chase Francis".
            let offsets = occurrences(of: heard, in: write)
            for m in matches.reversed() {
                guard let r = Range(m.range, in: s) else { continue }
                if alreadyWritten(s, matchStart: r.lowerBound, write: write, offsets: offsets) { continue }
                s.replaceSubrange(r, with: write)
            }
        }
        return s
    }

    /// Character offsets at which `needle` occurs in `haystack`, ignoring case.
    private static func occurrences(of needle: String, in haystack: String) -> [Int] {
        var out: [Int] = []
        var from = haystack.startIndex
        while let r = haystack.range(of: needle, options: .caseInsensitive, range: from..<haystack.endIndex) {
            out.append(haystack.distance(from: haystack.startIndex, to: r.lowerBound))
            from = haystack.index(after: r.lowerBound)
        }
        return out
    }

    private static func alreadyWritten(_ s: String, matchStart: String.Index, write: String, offsets: [Int]) -> Bool {
        for off in offsets {
            guard let start = s.index(matchStart, offsetBy: -off, limitedBy: s.startIndex) else { continue }
            if s[start...].hasPrefix(write) { return true }
        }
        return false
    }
}
