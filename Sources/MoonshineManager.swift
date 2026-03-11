import Foundation
import MoonshineVoice

private func moonLog(_ msg: String) {
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

class MoonshineManager {
    enum Model: String, CaseIterable {
        case tiny = "moonshine-tiny"

        var modelArch: ModelArch {
            switch self {
            case .tiny: return .tiny
            }
        }

        /// Folder name inside the framework bundle's test-assets
        var bundledModelDir: String {
            switch self {
            case .tiny: return "tiny-en"
            }
        }

        var displayName: String {
            switch self {
            case .tiny: return "Moonshine Tiny"
            }
        }
    }

    private var transcriber: Transcriber?
    private(set) var loadedModel: Model?

    func loadModel(_ model: Model) async -> Bool {
        if loadedModel == model && transcriber != nil {
            moonLog("Moonshine model already loaded: \(model.rawValue)")
            return true
        }

        moonLog("Loading Moonshine model: \(model.rawValue)")

        guard let bundle = Transcriber.frameworkBundle else {
            moonLog("Could not find Moonshine framework bundle")
            return false
        }

        guard let resourcePath = bundle.resourcePath else {
            moonLog("Could not find Moonshine resource path")
            return false
        }

        let modelPath = resourcePath + "/test-assets/" + model.bundledModelDir
        moonLog("Moonshine model path: \(modelPath)")

        let fm = FileManager.default
        guard fm.fileExists(atPath: modelPath) else {
            moonLog("Moonshine model directory not found at \(modelPath)")
            return false
        }

        do {
            let t = try Transcriber(modelPath: modelPath, modelArch: model.modelArch)
            transcriber = t
            loadedModel = model
            moonLog("Moonshine model loaded: \(model.rawValue)")
            return true
        } catch {
            moonLog("Failed to load Moonshine model: \(error)")
            return false
        }
    }

    func transcribe(samples: [Float]) async -> String {
        guard let t = transcriber else {
            moonLog("Moonshine not loaded")
            return ""
        }

        do {
            let startTime = CFAbsoluteTimeGetCurrent()
            let audioDuration = Double(samples.count) / 16000.0

            let transcript = try t.transcribeWithoutStreaming(audioData: samples, sampleRate: 16000)

            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
            moonLog("Moonshine transcribed \(String(format: "%.1f", audioDuration))s audio in \(String(format: "%.2f", elapsed))s (\(String(format: "%.1f", audioDuration / elapsed))x realtime)")

            let text = transcript.lines.map { $0.text }.joined(separator: " ")
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            moonLog("Moonshine transcription error: \(error)")
            return ""
        }
    }
}
