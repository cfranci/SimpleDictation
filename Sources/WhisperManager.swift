import Foundation
import WhisperKit

class WhisperManager {
    enum Model: String, CaseIterable {
        case tiny = "whisper-tiny"
        case base = "whisper-base"
        case small = "whisper-small"
        case medium = "whisper-medium"

        var whisperKitModel: String {
            switch self {
            case .tiny: return "openai_whisper-tiny"
            case .base: return "openai_whisper-base"
            case .small: return "openai_whisper-small"
            case .medium: return "openai_whisper-medium"
            }
        }

        var displayName: String {
            switch self {
            case .tiny: return "Whisper Tiny"
            case .base: return "Whisper Base"
            case .small: return "Whisper Small"
            case .medium: return "Whisper Medium"
            }
        }
    }

    private var whisperKit: WhisperKit?
    private(set) var loadedModel: Model?

    func loadModel(_ model: Model) async -> Bool {
        if loadedModel == model && whisperKit != nil {
            NSLog("[SimpleDictation] WhisperKit model already loaded: %@", model.rawValue)
            return true
        }

        NSLog("[SimpleDictation] Loading WhisperKit model: %@", model.whisperKitModel)

        do {
            let kit = try await WhisperKit(model: model.whisperKitModel)
            whisperKit = kit
            loadedModel = model
            NSLog("[SimpleDictation] WhisperKit model loaded: %@", model.rawValue)
            return true
        } catch {
            NSLog("[SimpleDictation] Failed to load WhisperKit model: %@", error.localizedDescription)
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
