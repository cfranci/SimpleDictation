import Foundation
import WhisperKit

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

    func loadModel(_ model: Model) async -> Bool {
        if loadedModel == model && whisperKit != nil {
            debugLog("WhisperKit model already loaded: \(model.rawValue)")
            return true
        }

        debugLog("Loading WhisperKit model: \(model.whisperKitModel)")

        do {
            let kit = try await WhisperKit(model: model.whisperKitModel)
            whisperKit = kit
            loadedModel = model
            debugLog("WhisperKit model loaded successfully: \(model.rawValue)")
            return true
        } catch {
            debugLog("Failed to load WhisperKit model '\(model.whisperKitModel)': \(error)")
            return false
        }
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
