import Foundation
#if canImport(WhisperKit)
import WhisperKit
#endif

private func debugLog(_ msg: String) {
    NSLog("[SimpleDictation] %@", msg)
    let line = "\(Date()): \(msg)\n"
    let path = "/tmp/simpledictation.log"
    if let handle = FileHandle(forWritingAtPath: path) {
        handle.seekToEndOfFile()
        handle.write(line.data(using: .utf8)!)
        handle.closeFile()
    } else {
        FileManager.default.createFile(atPath: path, contents: line.data(using: .utf8))
    }
}

@available(macOS 14, *)
class WhisperManager {
    enum Model: String, CaseIterable {
        case tiny = "whisper-tiny"
        case base = "whisper-base"
        case small = "whisper-small"
        case medium = "whisper-medium"
        case distilLargeV3 = "distil-large-v3"
        case distilLargeV3Turbo = "distil-large-v3-turbo"

        var whisperKitModel: String {
            switch self {
            case .tiny: return "openai_whisper-tiny"
            case .base: return "openai_whisper-base"
            case .small: return "openai_whisper-small"
            case .medium: return "openai_whisper-medium"
            case .distilLargeV3: return "distil-whisper_distil-large-v3"
            case .distilLargeV3Turbo: return "distil-whisper_distil-large-v3_turbo"
            }
        }

        var displayName: String {
            switch self {
            case .tiny: return "Whisper Tiny"
            case .base: return "Whisper Base"
            case .small: return "Whisper Small"
            case .medium: return "Whisper Medium"
            case .distilLargeV3: return "Distil-Whisper Large v3"
            case .distilLargeV3Turbo: return "Distil-Whisper Large v3 Turbo"
            }
        }
    }

    private var whisperKit: WhisperKit?
    private(set) var loadedModel: Model?

    /// Called when a model starts downloading/loading (true) and when done (false, success)
    var onModelLoading: ((Bool, Model, Bool) -> Void)?

    func loadModel(_ model: Model) async -> Bool {
        if loadedModel == model && whisperKit != nil {
            debugLog("WhisperKit model already loaded: \(model.rawValue)")
            return true
        }

        debugLog("Loading WhisperKit model: \(model.whisperKitModel)")
        await MainActor.run { onModelLoading?(true, model, false) }

        let startTime = CFAbsoluteTimeGetCurrent()
        do {
            let kit = try await WhisperKit(model: model.whisperKitModel)
            whisperKit = kit
            loadedModel = model
            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
            debugLog("WhisperKit model loaded successfully: \(model.rawValue) in \(String(format: "%.1f", elapsed))s")
            await MainActor.run { onModelLoading?(false, model, true) }
            return true
        } catch {
            debugLog("Failed to load WhisperKit model '\(model.whisperKitModel)': \(error)")
            await MainActor.run { onModelLoading?(false, model, false) }
            return false
        }
    }

    /// Check if a model is available locally (already downloaded).
    /// WhisperKit uses ~/Library/Caches/ or the HF hub cache.
    func isModelLocal(_ model: Model) -> Bool {
        let fm = FileManager.default
        // WhisperKit stores models under huggingface hub cache
        let hubCache = NSHomeDirectory() + "/.cache/huggingface/hub"
        let modelName = "models--argmaxinc--whisperkit-coreml"
        let modelDir = hubCache + "/" + modelName
        if fm.fileExists(atPath: modelDir) {
            // Check for the specific model variant in snapshots
            if let snapshots = try? fm.contentsOfDirectory(atPath: modelDir + "/snapshots") {
                for snap in snapshots {
                    let variantPath = modelDir + "/snapshots/" + snap + "/" + model.whisperKitModel
                    if fm.fileExists(atPath: variantPath) {
                        return true
                    }
                }
            }
        }
        // Also check if it's the currently loaded model
        return loadedModel == model && whisperKit != nil
    }

    func transcribe(samples: [Float], language: String? = nil) async -> String {
        guard let kit = whisperKit else {
            NSLog("[SimpleDictation] WhisperKit not loaded")
            return ""
        }

        do {
            let startTime = CFAbsoluteTimeGetCurrent()
            let audioDuration = Double(samples.count) / 16000.0

            let options = DecodingOptions(language: language)
            let results = try await kit.transcribe(audioArray: samples, decodeOptions: options)

            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
            NSLog("[SimpleDictation] Whisper transcribed %.1fs audio in %.2fs (%.1fx realtime)", audioDuration, elapsed, audioDuration / elapsed)

            let text = results.map { $0.text }.joined(separator: " ")
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            NSLog("[SimpleDictation] WhisperKit transcription error: %@", error.localizedDescription)
            return ""
        }
    }
}
