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
        case largev3Turbo = "whisper-large-v3-turbo"
        case largev3TurboCompressed = "whisper-large-v3-turbo-632"

        var whisperKitModel: String {
            switch self {
            case .tiny: return "openai_whisper-tiny"
            case .base: return "openai_whisper-base"
            case .small: return "openai_whisper-small"
            case .medium: return "openai_whisper-medium"
            case .distilLargeV3: return "distil-whisper_distil-large-v3"
            case .distilLargeV3Turbo: return "distil-whisper_distil-large-v3_turbo"
            case .largev3Turbo: return "openai_whisper-large-v3-v20240930_turbo"
            case .largev3TurboCompressed: return "openai_whisper-large-v3-v20240930_turbo_632MB"
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
            case .largev3Turbo: return "Whisper Large v3 Turbo"
            case .largev3TurboCompressed: return "Whisper Large v3 Turbo (632MB)"
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

    /// Root folder WhisperKit actually downloads its CoreML models into.
    static var modelStoreRoot: String {
        NSHomeDirectory() + "/Documents/huggingface/models/argmaxinc/whisperkit-coreml"
    }

    /// On-disk folder for a specific model variant.
    func modelDirectory(_ model: Model) -> String {
        WhisperManager.modelStoreRoot + "/" + model.whisperKitModel
    }

    /// Check if a model is available locally (already downloaded). WhisperKit
    /// stores models under ~/Documents/huggingface/models/argmaxinc/whisperkit-coreml
    /// — NOT the HF hub cache — so we look there for the compiled CoreML bundles.
    func isModelLocal(_ model: Model) -> Bool {
        if loadedModel == model && whisperKit != nil { return true }
        let fm = FileManager.default
        let dir = modelDirectory(model)
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: dir, isDirectory: &isDir), isDir.boolValue else { return false }
        // A complete model has the compiled .mlmodelc bundles.
        let contents = (try? fm.contentsOfDirectory(atPath: dir)) ?? []
        return contents.contains { $0.hasSuffix(".mlmodelc") }
    }

    /// Every Whisper model currently downloaded on disk.
    func localModels() -> [Model] {
        Model.allCases.filter { isModelLocal($0) }
    }

    /// Delete a downloaded model's folder to reclaim disk. Never deletes the
    /// model that's currently loaded in memory.
    @discardableResult
    func deleteModel(_ model: Model) -> Bool {
        guard model != loadedModel else { return false }
        do {
            try FileManager.default.removeItem(atPath: modelDirectory(model))
            debugLog("Deleted local model \(model.rawValue)")
            return true
        } catch {
            debugLog("Failed to delete model \(model.rawValue): \(error)")
            return false
        }
    }

    /// Remove every downloaded model except the one to keep — backs the
    /// "keep only selected model" disk-cleanup option.
    func pruneOtherModels(keeping keep: Model) {
        for m in localModels() where m != keep { deleteModel(m) }
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
