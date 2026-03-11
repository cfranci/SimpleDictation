import Foundation
import Speech
import AVFoundation
import Cocoa
import CoreAudio

class SpeechManager: NSObject, ObservableObject, SFSpeechRecognizerDelegate {
    @Published var recognizedText: String = ""
    @Published var audioLevel: Float = 0.0
    @Published var isRecording: Bool = false
    @Published var isAuthorized: Bool = false
    @Published var availableMics: [AudioDeviceInfo] = []
    @Published var selectedMicID: AudioDeviceID = 0
    @Published var currentLocale: String = "en-US"
    @Published var engineMode: String = "apple" // "apple", "whisper-tiny", "whisper-base", "whisper-small", "whisper-medium", "distil-large-v3", "distil-large-v3-turbo", "moonshine-tiny", "moonshine-base"

    static let supportedLocales: [(id: String, name: String)] = [
        ("en-US", "English (US)"),
        ("en-GB", "English (UK)"),
        ("en-AU", "English (Australia)"),
        ("es-ES", "Spanish"),
        ("es-MX", "Spanish (Mexico)"),
        ("fr-FR", "French"),
        ("de-DE", "German"),
        ("it-IT", "Italian"),
        ("pt-BR", "Portuguese (Brazil)"),
        ("zh-Hans", "Chinese (Simplified)"),
        ("zh-Hant", "Chinese (Traditional)"),
        ("ja-JP", "Japanese"),
        ("ko-KR", "Korean"),
        ("hi-IN", "Hindi"),
        ("ar-SA", "Arabic"),
        ("ru-RU", "Russian"),
    ]

    var onTextRecognized: ((String) -> Void)?

    var hasPasted: Bool = false
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var audioEngine: AVAudioEngine?

    // Whisper state
    let whisperManager = WhisperManager()
    let moonshineManager = MoonshineManager()
    private var whisperSamples: [Float] = []
    private var whisperPastedCharCount: Int = 0  // chars currently on screen (including trailing space)
    private var isIncrementalTranscribing = false
    private var whisperTimer: Timer?
    private var whisperSessionID: UInt64 = 0  // incremented each recording to discard stale results

    struct AudioDeviceInfo: Identifiable {
        let id: AudioDeviceID
        let name: String
    }

    override init() {
        super.init()
        refreshMicList()
    }

    func setLocale(_ localeID: String) {
        currentLocale = localeID
        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: localeID))
        speechRecognizer?.delegate = self
    }

    private func ensureRecognizer() {
        if speechRecognizer == nil {
            speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: currentLocale))
            speechRecognizer?.delegate = self
        }
    }

    func checkAuthorization() {
        NSLog("[SimpleDictation] Checking authorization...")
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
            NSLog("[SimpleDictation] Microphone access: %d", granted)
            guard granted else {
                DispatchQueue.main.async { self?.isAuthorized = false }
                return
            }
            SFSpeechRecognizer.requestAuthorization { status in
                NSLog("[SimpleDictation] Speech recognition status: %d", status.rawValue)
                DispatchQueue.main.async {
                    self?.isAuthorized = (status == .authorized)
                    NSLog("[SimpleDictation] isAuthorized set to: %d", self?.isAuthorized ?? false)
                }
            }
        }
    }

    func refreshMicList() {
        var propAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &propAddress, 0, nil, &dataSize) == noErr else { return }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &propAddress, 0, nil, &dataSize, &deviceIDs) == noErr else { return }

        var mics: [AudioDeviceInfo] = []
        for id in deviceIDs {
            var inputAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreamConfiguration,
                mScope: kAudioDevicePropertyScopeInput,
                mElement: kAudioObjectPropertyElementMain
            )
            var inputSize: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(id, &inputAddress, 0, nil, &inputSize) == noErr else { continue }

            let bufferListPtr = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: 1)
            defer { bufferListPtr.deallocate() }
            guard AudioObjectGetPropertyData(id, &inputAddress, 0, nil, &inputSize, bufferListPtr) == noErr else { continue }

            let bufferList = UnsafeMutableAudioBufferListPointer(bufferListPtr)
            let inputChannels = bufferList.reduce(0) { $0 + Int($1.mNumberChannels) }
            guard inputChannels > 0 else { continue }

            var nameAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceNameCFString,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var name: CFString = "" as CFString
            var nameSize = UInt32(MemoryLayout<CFString>.size)
            guard AudioObjectGetPropertyData(id, &nameAddress, 0, nil, &nameSize, &name) == noErr else { continue }

            mics.append(AudioDeviceInfo(id: id, name: name as String))
        }

        availableMics = mics
        if selectedMicID == 0, let first = mics.first {
            selectedMicID = first.id
        }
    }

    func selectMic(_ deviceID: AudioDeviceID) {
        selectedMicID = deviceID
    }

    private func setInputDevice(_ deviceID: AudioDeviceID) {
        var deviceID = deviceID
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0, nil,
            UInt32(MemoryLayout<AudioDeviceID>.size),
            &deviceID
        )
    }

    private var isMoonshineEngine: Bool {
        engineMode.hasPrefix("moonshine-")
    }

    private func slog(_ msg: String) {
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

    // MARK: - Recording Dispatch

    func startRecording() {
        slog("startRecording: engineMode=\(engineMode)")
        if isMoonshineEngine {
            startMoonshineRecording()
            return
        }
        if engineMode != "apple" {
            startWhisperRecording()
            return
        }

        guard isAuthorized else {
            NSLog("[SimpleDictation] Not authorized, requesting auth")
            checkAuthorization()
            return
        }

        ensureRecognizer()
        hasPasted = false
        recognizedText = ""

        stopAppleRecording()

        if selectedMicID != 0 {
            setInputDevice(selectedMicID)
        }

        guard let recognizer = speechRecognizer else {
            NSLog("[SimpleDictation] No speech recognizer")
            return
        }
        guard recognizer.isAvailable else {
            NSLog("[SimpleDictation] Speech recognizer not available")
            return
        }

        let engine = AVAudioEngine()
        audioEngine = engine

        let inputNode = engine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        NSLog("[SimpleDictation] Audio format: %@", recordingFormat.description)

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            NSLog("[SimpleDictation] Failed to create recognition request")
            return
        }

        recognitionRequest.shouldReportPartialResults = true
        if #available(macOS 13.0, *) {
            recognitionRequest.addsPunctuation = true
        }

        var bufferCount = 0
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
            bufferCount += 1
            if bufferCount == 1 {
                NSLog("[SimpleDictation] First audio buffer received, frames: %d", buffer.frameLength)
            }

            guard let channelData = buffer.floatChannelData?[0] else { return }
            let frames = Int(buffer.frameLength)
            let rms = sqrt((0..<frames).reduce(Float(0)) { $0 + channelData[$1] * channelData[$1] } / Float(frames))
            let avgPower = 20 * log10(max(rms, 0.000001))
            let normalized = max(0.0, (avgPower + 50) / 50.0)
            DispatchQueue.main.async {
                self?.audioLevel = normalized
            }
        }

        do {
            engine.prepare()
            try engine.start()
            NSLog("[SimpleDictation] Engine started successfully")
        } catch {
            NSLog("[SimpleDictation] Engine start failed: %@", error.localizedDescription)
            audioEngine = nil
            self.recognitionRequest = nil
            return
        }

        isRecording = true

        NSLog("[SimpleDictation] Waiting for audio to flow before starting recognition...")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self = self, self.isRecording, let recognitionRequest = self.recognitionRequest else { return }
            NSLog("[SimpleDictation] Starting recognition task, supportsOnDevice: %d, buffers so far: %d", recognizer.supportsOnDeviceRecognition, bufferCount)

            self.recognitionTask = recognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
                guard let self = self else { return }
                var isFinal = false

                if let result = result {
                    NSLog("[SimpleDictation] Got result: %@, isFinal: %d", result.bestTranscription.formattedString, result.isFinal)
                    self.recognizedText = result.bestTranscription.formattedString
                    isFinal = result.isFinal
                }

                if let error = error {
                    NSLog("[SimpleDictation] Recognition error: %@", error.localizedDescription)
                }

                if error != nil || isFinal {
                    self.audioEngine?.stop()
                    self.audioEngine?.inputNode.removeTap(onBus: 0)
                    self.audioEngine = nil
                    self.recognitionRequest = nil
                    self.recognitionTask = nil
                    self.isRecording = false

                    if !self.recognizedText.isEmpty && !self.hasPasted {
                        self.hasPasted = true
                        self.onTextRecognized?(self.recognizedText)
                    }
                }
            }
        }
    }

    func stopRecording() {
        if isMoonshineEngine {
            stopMoonshineRecording()
            return
        }
        if engineMode != "apple" {
            stopWhisperRecording()
            return
        }
        stopAppleRecording()
    }

    private func stopAppleRecording() {
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        isRecording = false
    }

    // MARK: - Whisper Recording

    private func whisperModel(for mode: String) -> WhisperManager.Model {
        switch mode {
        case "whisper-tiny": return .tiny
        case "whisper-base": return .base
        case "whisper-small": return .small
        case "whisper-medium": return .medium
        case "distil-large-v3": return .distilLargeV3
        case "distil-large-v3-turbo": return .distilLargeV3Turbo
        default: return .base
        }
    }

    private var whisperLanguageCode: String {
        return String(currentLocale.prefix(2))
    }

    func preloadWhisperModel() {
        let model = whisperModel(for: engineMode)
        NSLog("[SimpleDictation] Pre-loading whisper model: %@", model.rawValue)
        Task {
            let _ = await whisperManager.loadModel(model)
        }
    }

    private func startWhisperRecording() {
        hasPasted = false
        recognizedText = ""
        whisperSamples = []
        whisperPastedCharCount = 0
        isIncrementalTranscribing = false
        whisperSessionID &+= 1

        stopWhisperRecordingInternal()

        if selectedMicID != 0 {
            setInputDevice(selectedMicID)
        }

        let model = whisperModel(for: engineMode)

        // Always go through loadModel — it's a no-op if already loaded with the right model
        Task {
            let loaded = await whisperManager.loadModel(model)
            guard loaded else {
                NSLog("[SimpleDictation] Failed to load whisper model")
                return
            }
            await MainActor.run {
                self.startWhisperAudioCapture()
            }
        }
    }

    private func startWhisperAudioCapture() {
        let engine = AVAudioEngine()
        audioEngine = engine

        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        NSLog("[SimpleDictation] Whisper input format: %@", inputFormat.description)

        guard let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false) else {
            NSLog("[SimpleDictation] Failed to create 16kHz format")
            return
        }

        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            NSLog("[SimpleDictation] Failed to create audio converter")
            return
        }

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            guard let self = self else { return }

            // Audio level
            if let channelData = buffer.floatChannelData?[0] {
                let frames = Int(buffer.frameLength)
                let rms = sqrt((0..<frames).reduce(Float(0)) { $0 + channelData[$1] * channelData[$1] } / Float(frames))
                let avgPower = 20 * log10(max(rms, 0.000001))
                let normalized = max(0.0, (avgPower + 50) / 50.0)
                DispatchQueue.main.async {
                    self.audioLevel = normalized
                }
            }

            // Convert to 16kHz mono
            let ratio = targetFormat.sampleRate / inputFormat.sampleRate
            let outputFrameCount = AVAudioFrameCount(Double(buffer.frameLength) * ratio)
            guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputFrameCount) else { return }

            var error: NSError?
            let status = converter.convert(to: outputBuffer, error: &error) { inNumPackets, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }

            guard status != .error, error == nil else {
                NSLog("[SimpleDictation] Audio conversion error: %@", error?.localizedDescription ?? "unknown")
                return
            }

            if let floatData = outputBuffer.floatChannelData?[0] {
                let count = Int(outputBuffer.frameLength)
                let samples = Array(UnsafeBufferPointer(start: floatData, count: count))
                DispatchQueue.main.async {
                    self.whisperSamples.append(contentsOf: samples)
                }
            }
        }

        do {
            engine.prepare()
            try engine.start()
            NSLog("[SimpleDictation] Whisper audio engine started")
        } catch {
            NSLog("[SimpleDictation] Whisper engine start failed: %@", error.localizedDescription)
            audioEngine = nil
            return
        }

        isRecording = true

        // Incremental transcription every 5 seconds
        whisperTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.performIncrementalTranscription()
        }
    }

    private func performIncrementalTranscription() {
        guard !isIncrementalTranscribing else { return }
        let samples = whisperSamples
        guard samples.count > 16000 else { return } // Need at least 1s

        isIncrementalTranscribing = true
        let langCode = whisperLanguageCode
        let sessionID = whisperSessionID
        Task {
            let text = await whisperManager.transcribe(samples: samples, language: langCode)

            await MainActor.run {
                self.isIncrementalTranscribing = false
                // Discard if this is from a stale session
                guard self.whisperSessionID == sessionID, self.isRecording, !text.isEmpty else { return }

                self.recognizedText = text
                NSLog("[SimpleDictation] Whisper incremental: %@", text)

                // Delete old text and replace with full new transcription
                self.deleteAndPaste(text)
            }
        }
    }

    /// Delete previously pasted text (via backspaces) then paste the new full text
    private func deleteAndPaste(_ newText: String) {
        // Delete old pasted text
        if whisperPastedCharCount > 0 {
            let src = CGEventSource(stateID: .hidSystemState)
            for _ in 0..<whisperPastedCharCount {
                let down = CGEvent(keyboardEventSource: src, virtualKey: 51, keyDown: true)
                down?.post(tap: .cghidEventTap)
                let up = CGEvent(keyboardEventSource: src, virtualKey: 51, keyDown: false)
                up?.post(tap: .cghidEventTap)
            }
            usleep(30000)
        }

        // Paste new full text (pasteText adds trailing space)
        pasteText(newText)
        whisperPastedCharCount = newText.count + 1 // +1 for the trailing space pasteText adds
    }

    private func stopWhisperRecording() {
        whisperTimer?.invalidate()
        whisperTimer = nil

        let hadEngine = audioEngine != nil
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil
        isRecording = false

        guard hadEngine else { return }

        let samples = whisperSamples
        guard samples.count > 8000 else {
            NSLog("[SimpleDictation] Whisper: too few samples (%d) for transcription", samples.count)
            return
        }

        NSLog("[SimpleDictation] Whisper final transcription: %d samples (%.1fs)", samples.count, Float(samples.count) / 16000.0)

        let langCode = whisperLanguageCode
        Task {
            let text = await whisperManager.transcribe(samples: samples, language: langCode)

            await MainActor.run {
                guard !text.isEmpty else { return }
                self.recognizedText = text
                NSLog("[SimpleDictation] Whisper final: %@", text)

                // Delete old incremental text and replace with final full transcription
                self.deleteAndPaste(text)

                // Put the full transcript in the clipboard so user can access it
                usleep(100000)
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(text, forType: .string)
                NSLog("[SimpleDictation] Full transcript placed in clipboard (%d chars)", text.count)
            }
        }
    }

    private func stopWhisperRecordingInternal() {
        whisperTimer?.invalidate()
        whisperTimer = nil
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil
        isRecording = false
    }

    // MARK: - Moonshine Recording

    private func moonshineModel(for mode: String) -> MoonshineManager.Model {
        switch mode {
        case "moonshine-tiny": return .tiny
        default: return .tiny
        }
    }

    func preloadMoonshineModel() {
        let model = moonshineModel(for: engineMode)
        NSLog("[SimpleDictation] Pre-loading Moonshine model: %@", model.rawValue)
        Task {
            let _ = await moonshineManager.loadModel(model)
        }
    }

    private func startMoonshineRecording() {
        hasPasted = false
        recognizedText = ""
        whisperSamples = []
        whisperPastedCharCount = 0
        isIncrementalTranscribing = false
        whisperSessionID &+= 1

        stopMoonshineRecordingInternal()

        if selectedMicID != 0 {
            setInputDevice(selectedMicID)
        }

        let model = moonshineModel(for: engineMode)

        Task {
            let loaded = await moonshineManager.loadModel(model)
            guard loaded else {
                NSLog("[SimpleDictation] Failed to load Moonshine model")
                return
            }
            await MainActor.run {
                self.startMoonshineAudioCapture()
            }
        }
    }

    private func startMoonshineAudioCapture() {
        let engine = AVAudioEngine()
        audioEngine = engine

        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        NSLog("[SimpleDictation] Moonshine input format: %@", inputFormat.description)

        guard let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false) else {
            NSLog("[SimpleDictation] Failed to create 16kHz format")
            return
        }

        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            NSLog("[SimpleDictation] Failed to create audio converter")
            return
        }

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            guard let self = self else { return }

            if let channelData = buffer.floatChannelData?[0] {
                let frames = Int(buffer.frameLength)
                let rms = sqrt((0..<frames).reduce(Float(0)) { $0 + channelData[$1] * channelData[$1] } / Float(frames))
                let avgPower = 20 * log10(max(rms, 0.000001))
                let normalized = max(0.0, (avgPower + 50) / 50.0)
                DispatchQueue.main.async {
                    self.audioLevel = normalized
                }
            }

            let ratio = targetFormat.sampleRate / inputFormat.sampleRate
            let outputFrameCount = AVAudioFrameCount(Double(buffer.frameLength) * ratio)
            guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputFrameCount) else { return }

            var error: NSError?
            let status = converter.convert(to: outputBuffer, error: &error) { inNumPackets, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }

            guard status != .error, error == nil else {
                NSLog("[SimpleDictation] Audio conversion error: %@", error?.localizedDescription ?? "unknown")
                return
            }

            if let floatData = outputBuffer.floatChannelData?[0] {
                let count = Int(outputBuffer.frameLength)
                let samples = Array(UnsafeBufferPointer(start: floatData, count: count))
                DispatchQueue.main.async {
                    self.whisperSamples.append(contentsOf: samples)
                }
            }
        }

        do {
            engine.prepare()
            try engine.start()
            NSLog("[SimpleDictation] Moonshine audio engine started")
        } catch {
            NSLog("[SimpleDictation] Moonshine engine start failed: %@", error.localizedDescription)
            audioEngine = nil
            return
        }

        isRecording = true

        // Incremental transcription every 5 seconds
        whisperTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.performMoonshineIncrementalTranscription()
        }
    }

    private func performMoonshineIncrementalTranscription() {
        guard !isIncrementalTranscribing else { return }
        let samples = whisperSamples
        guard samples.count > 16000 else { return }

        isIncrementalTranscribing = true
        let sessionID = whisperSessionID
        Task {
            let text = await moonshineManager.transcribe(samples: samples)

            await MainActor.run {
                self.isIncrementalTranscribing = false
                guard self.whisperSessionID == sessionID, self.isRecording, !text.isEmpty else { return }

                self.recognizedText = text
                NSLog("[SimpleDictation] Moonshine incremental: %@", text)
                self.deleteAndPaste(text)
            }
        }
    }

    private func stopMoonshineRecording() {
        whisperTimer?.invalidate()
        whisperTimer = nil

        let hadEngine = audioEngine != nil
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil
        isRecording = false

        guard hadEngine else { return }

        let samples = whisperSamples
        guard samples.count > 8000 else {
            NSLog("[SimpleDictation] Moonshine: too few samples (%d) for transcription", samples.count)
            return
        }

        NSLog("[SimpleDictation] Moonshine final transcription: %d samples (%.1fs)", samples.count, Float(samples.count) / 16000.0)

        Task {
            let text = await moonshineManager.transcribe(samples: samples)

            await MainActor.run {
                guard !text.isEmpty else { return }
                self.recognizedText = text
                NSLog("[SimpleDictation] Moonshine final: %@", text)

                self.deleteAndPaste(text)

                usleep(100000)
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(text, forType: .string)
                NSLog("[SimpleDictation] Full transcript placed in clipboard (%d chars)", text.count)
            }
        }
    }

    private func stopMoonshineRecordingInternal() {
        whisperTimer?.invalidate()
        whisperTimer = nil
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil
        isRecording = false
    }

    // MARK: - Keypress Helpers

    func pressEnter() {
        let src = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: src, virtualKey: 36, keyDown: true)
        down?.post(tap: .cghidEventTap)
        let up = CGEvent(keyboardEventSource: src, virtualKey: 36, keyDown: false)
        up?.post(tap: .cghidEventTap)
    }

    // MARK: - Paste

    func pasteText(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let textToPaste = text + " "
        pasteboard.setString(textToPaste, forType: .string)

        usleep(50000)

        let src = CGEventSource(stateID: .hidSystemState)

        let cmdDown = CGEvent(keyboardEventSource: src, virtualKey: 55, keyDown: true)
        cmdDown?.flags = .maskCommand
        cmdDown?.post(tap: .cghidEventTap)

        usleep(50000)

        let vDown = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: true)
        vDown?.flags = .maskCommand
        vDown?.post(tap: .cghidEventTap)

        usleep(50000)

        let vUp = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: false)
        vUp?.flags = .maskCommand
        vUp?.post(tap: .cghidEventTap)

        usleep(50000)

        let cmdUp = CGEvent(keyboardEventSource: src, virtualKey: 55, keyDown: false)
        cmdUp?.post(tap: .cghidEventTap)
    }
}
