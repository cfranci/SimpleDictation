import Foundation

/// Drives the Cactus Whistle on-device speech-to-text model through the Needle
/// C engine (libneedle.a, bridged via needle.h). Whistle is a single ~17 MB
/// `.cact` file bundled in the app — CPU-only, no downloads, no GPU. The engine
/// keeps one process-global, non-thread-safe speech model, so every call is
/// serialized through a recursive lock.
final class WhistleManager {
    private(set) var isLoaded = false
    private let lock = NSRecursiveLock()

    private func log(_ msg: String) {
        NSLog("[SimpleDictation] Whistle: %@", msg)
        let line = "\(Date()): Whistle: \(msg)\n"
        let path = "/tmp/simpledictation.log"
        if let h = FileHandle(forWritingAtPath: path) {
            h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); h.closeFile()
        } else {
            FileManager.default.createFile(atPath: path, contents: line.data(using: .utf8))
        }
    }

    /// True once whistle.cact is in the app bundle (always, since it's a resource).
    var isModelLocal: Bool {
        Bundle.main.url(forResource: "whistle", withExtension: "cact") != nil
    }

    /// Load whistle.cact into the Needle engine. Idempotent; cheap after the first.
    @discardableResult
    func load() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if isLoaded { return true }
        guard let url = Bundle.main.url(forResource: "whistle", withExtension: "cact"),
              let data = try? Data(contentsOf: url) else {
            log("whistle.cact not found in bundle")
            return false
        }
        let rc = data.withUnsafeBytes { raw -> Int32 in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return -1 }
            return needle_load(base, UInt64(data.count))
        }
        guard rc >= 0 else {
            log("needle_load failed: \(lastError())")
            return false
        }
        isLoaded = true
        log("model loaded (\(data.count) bytes)")
        return true
    }

    /// Transcribe 16 kHz mono float PCM in [-1, 1]. `language` is "en"/"de"/… or
    /// nil to auto-detect. Silence/steady noise returns an empty string.
    func transcribe(samples: [Float], language: String? = nil, keywords: String? = nil) -> String {
        lock.lock(); defer { lock.unlock() }
        guard load() else { return "" }
        var out = [CChar](repeating: 0, count: 1 << 16)   // 64 KB — plenty for a 30 s window
        let n: Int32 = samples.withUnsafeBufferPointer { buf in
            withOptionalCString(language) { langPtr in
                withOptionalCString(keywords) { kwPtr in
                    needle_transcribe(buf.baseAddress, Int32(buf.count),
                                      langPtr, kwPtr, 0, &out, Int32(out.count))
                }
            }
        }
        guard n >= 0 else {
            log("transcribe failed: \(lastError())")
            return ""
        }
        return Self.extractText(String(cString: out))
    }

    private func lastError() -> String {
        guard let c = needle_last_error() else { return "unknown" }
        return String(cString: c)
    }

    /// Pull the "text" field out of Needle's JSON result.
    private static func extractText(_ json: String) -> String {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = obj["text"] as? String else { return "" }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Call `body` with a C string for `s`, or NULL when `s` is nil.
private func withOptionalCString<R>(_ s: String?, _ body: (UnsafePointer<CChar>?) -> R) -> R {
    if let s = s { return s.withCString { body($0) } }
    return body(nil)
}
