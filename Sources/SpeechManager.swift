import Foundation
import Speech
import AVFoundation
import Cocoa
import CoreAudio

class SpeechManager: NSObject, ObservableObject, SFSpeechRecognizerDelegate {
    @Published var recognizedText: String = ""
    @Published var audioLevel: Float = 0.0
    @Published var isRecording: Bool = false {
        didSet { onRecordingStateChanged?(isRecording) }
    }
    @Published var isProcessing: Bool = false {
        didSet { onProcessingStateChanged?(isProcessing) }
    }
    @Published var isAuthorized: Bool = false
    @Published var availableMics: [AudioDeviceInfo] = []
    @Published var selectedMicID: AudioDeviceID = 0
    @Published var currentLocale: String = "en-US"
    @Published var engineMode: String = "apple" // "apple", "whisper-tiny", "whisper-base", "whisper-small", "whisper-medium", "distil-large-v3", "distil-large-v3-turbo", "whisper-large-v3-turbo", "whisper-large-v3-turbo-632", "moonshine-tiny"

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
    var onFallbackToApple: ((String) -> Void)?
    var onRecordingStateChanged: ((Bool) -> Void)?
    var onProcessingStateChanged: ((Bool) -> Void)?
    var incrementalMode: Bool = false  // Off by default: accumulate all, paste on stop

    /// Paste-as-you-speak. Now works in BOTH trigger modes: the incremental typer
    /// uses TextInjector (CGEventKeyboardSetUnicodeString from a private event source
    /// with empty flags), which the injection test proved types correctly even while
    /// the trigger key is physically held — so hold-to-talk no longer corrupts it.
    var incrementalActive: Bool { incrementalMode }

    /// Timestamp when recording actually started (used for short-recording guard)
    var recordingStartTime: Date?

    /// Known silence hallucinations that speech engines produce when no one speaks
    static let silenceHallucinations: Set<String> = [
        "thank you", "thanks", "thanks.", "thank you.", "thanks for watching",
        "thank you for watching", "bye", "bye.", "you", "you.", ".",
    ]

    /// Returns true if the transcript looks like a silence hallucination and should be suppressed
    func isSilenceHallucination(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Empty/whitespace only
        if trimmed.isEmpty { return true }
        // Known hallucination phrases
        if SpeechManager.silenceHallucinations.contains(trimmed.lowercased()) { return true }
        // Recording was too short (< 400ms of actual speech)
        if let start = recordingStartTime, Date().timeIntervalSince(start) < 0.4 { return true }
        return false
    }

    var hasPasted: Bool = false
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var audioEngine: AVAudioEngine?

    // Parallel Apple recognizer used ONLY to drive the live caption overlay when
    // the paste engine is Whisper/Moonshine (which don't stream word-by-word).
    // It reads the same mic buffers; it never types or pastes anything.
    private var captionRecognizer: SFSpeechRecognizer?
    private var captionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var captionTask: SFSpeechRecognitionTask?
    /// (text, isFinal) streamed live for captions.
    var onCaptionText: ((String, Bool) -> Void)?
    private var captionsEnabled: Bool {
        UserDefaults.standard.object(forKey: "captionEnabled") as? Bool ?? true
    }

    // Whisper state — only available on macOS 14+
    private var _whisperManager: AnyObject?
    private var _moonshineManager: AnyObject?

    @available(macOS 14, *)
    var whisperManager: WhisperManager {
        if _whisperManager == nil { _whisperManager = WhisperManager() }
        return _whisperManager as! WhisperManager
    }

    /// Cactus Whistle on-device engine (bundled .cact, CPU-only).
    let whistleManager = WhistleManager()
    var isWhistleEngine: Bool { engineMode == "whistle" }

    @available(macOS 14, *)
    var moonshineManager: MoonshineManager {
        if _moonshineManager == nil { _moonshineManager = MoonshineManager() }
        return _moonshineManager as! MoonshineManager
    }

    var canUseWhisper: Bool {
        if #available(macOS 14, *) { return true }
        return false
    }
    private var whisperSamples: [Float] = []
    /// Serial queue guarding whisperSamples. The audio tap appends on a background
    /// thread; stop reads a snapshot via sync so the final buffers can't land after
    /// the read (which dropped the tail of short utterances — "typed nothing").
    private let sampleQueue = DispatchQueue(label: "com.simpledictation.samples")
    private var whisperPastedCharCount: Int = 0  // chars currently on screen (including trailing space)
    private var whisperPastedText: String = ""   // the exact incremental text currently on screen (for diff replace)
    private var isIncrementalTranscribing = false
    private var whisperTimer: Timer?
    private var whisperSessionID: UInt64 = 0  // incremented each recording to discard stale results

    // Guard against overlapping Apple recognition starts
    private var pendingRecognitionStart: DispatchWorkItem?
    private var appleUserRequestedStop: Bool = false
    private var appleAccumulatedText: String = ""
    private var usingAppleFallback: Bool = false

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

    // MARK: - Live caption recognizer (parallel, non-Apple engines)

    /// Start a lightweight Apple recognizer purely to stream live caption text
    /// while Whisper/Moonshine capture audio for the actual transcription.
    private func startCaptionRecognizer() {
        guard captionsEnabled, isAuthorized else {
            slog("Caption recognizer skipped (captionsEnabled=\(captionsEnabled) authorized=\(isAuthorized))")
            return
        }
        stopCaptionRecognizer()

        let recognizer = SFSpeechRecognizer(locale: Locale(identifier: currentLocale))
        guard let recognizer = recognizer, recognizer.isAvailable else {
            slog("Caption recognizer unavailable")
            return
        }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        // Keep audio on this Mac whenever Apple has an on-device model for the
        // language. Only languages without one fall back to Apple's servers.
        request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        request.contextualStrings = TextPolish.vocabulary
        request.addsPunctuation = true
        captionRecognizer = recognizer
        captionRequest = request
        slog("Caption recognizer started (server-allowed, punctuation on)")
        captionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self = self else { return }
            if let result = result {
                let text = result.bestTranscription.formattedString
                if !text.isEmpty {
                    self.slog("CaptionLive(final=\(result.isFinal ? 1 : 0)): \(text)")
                    self.onCaptionText?(text, result.isFinal)
                }
            }
            if let error = error {
                self.slog("CaptionLive error: \(error.localizedDescription)")
            }
            if error != nil || (result?.isFinal ?? false) {
                // Task finished; buffers are no longer needed.
            }
        }
        NSLog("[SimpleDictation] Caption recognizer started (onDevice=%d)", recognizer.supportsOnDeviceRecognition)
    }

    /// Append a raw mic buffer to the caption recognizer (called from the tap).
    private func feedCaptionBuffer(_ buffer: AVAudioPCMBuffer) {
        captionRequest?.append(buffer)
    }

    private func stopCaptionRecognizer() {
        captionRequest?.endAudio()
        captionTask?.cancel()
        captionTask = nil
        captionRequest = nil
        captionRecognizer = nil
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

    // MARK: - Engine readiness

    /// Pick an engine that's ready to go at launch: keep the requested one if its
    /// model is already downloaded; otherwise fall back to any downloaded Whisper
    /// model, and finally Apple Speech (always built into macOS). The app never
    /// boots into a model that isn't on disk.
    func readyEngine(preferred: String) -> String {
        if preferred == "apple" { return "apple" }
        if preferred == "whistle" { return "whistle" }  // bundled .cact, always available
        guard #available(macOS 14, *) else { return "apple" }
        if preferred.hasPrefix("moonshine-") { return preferred }  // bundled, always available
        let model = whisperModel(for: preferred)
        if whisperManager.isModelLocal(model) { return preferred }
        if let firstLocal = whisperManager.localModels().first {
            slog("Saved engine '\(preferred)' isn't downloaded — defaulting to \(firstLocal.rawValue)")
            return firstLocal.rawValue
        }
        slog("No Whisper model downloaded — defaulting to Apple Speech")
        return "apple"
    }

    /// Delete every downloaded model except the currently-selected one.
    @available(macOS 14, *)
    func pruneModelsKeepingCurrent() {
        guard engineMode != "apple", !isMoonshineEngine else { return }
        whisperManager.pruneOtherModels(keeping: whisperModel(for: engineMode))
    }

    // MARK: - Recording Dispatch

    func startRecording() {
        slog("startRecording: engineMode=\(engineMode)")
        if isWhistleEngine { startWhistleRecording(); return }
        if #available(macOS 14, *) {
            if isMoonshineEngine {
                startMoonshineRecording()
                return
            }
            if engineMode != "apple" {
                let model = whisperModel(for: engineMode)
                if whisperManager.isModelLocal(model) || whisperManager.loadedModel == model {
                    startWhisperRecording()
                    return
                }
                // Model not ready, fall back to Apple while downloading
                slog("Whisper model \(model.rawValue) not ready, using Apple Speech as fallback")
                usingAppleFallback = true
                onFallbackToApple?(model.displayName)
                Task { let _ = await whisperManager.loadModel(model) }
                startAppleRecording()
                return
            }
        } else if engineMode != "apple" {
            slog("Whisper/Moonshine not available on this macOS, using Apple Speech")
            engineMode = "apple"
        }
        startAppleRecording()
    }

    private func startAppleRecording() {
        guard isAuthorized else {
            NSLog("[SimpleDictation] Not authorized, requesting auth")
            checkAuthorization()
            return
        }

        // Cancel any pending delayed recognition start from a previous session
        pendingRecognitionStart?.cancel()
        pendingRecognitionStart = nil

        ensureRecognizer()
        hasPasted = false
        recognizedText = ""
        recordingStartTime = Date()
        appleUserRequestedStop = false
        appleAccumulatedText = ""

        stopAppleRecordingInternal()

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
        recognitionRequest.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        recognitionRequest.contextualStrings = TextPolish.vocabulary
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
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self, self.isRecording, let recognitionRequest = self.recognitionRequest else { return }
            self.pendingRecognitionStart = nil
            NSLog("[SimpleDictation] Starting recognition task, supportsOnDevice: %d, buffers so far: %d", recognizer.supportsOnDeviceRecognition, bufferCount)

            self.recognitionTask = recognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
                guard let self = self else { return }

                if let result = result {
                    NSLog("[SimpleDictation] Got result: %@, isFinal: %d", result.bestTranscription.formattedString, result.isFinal)
                    self.recognizedText = result.bestTranscription.formattedString
                }

                if let error = error {
                    NSLog("[SimpleDictation] Recognition error: %@", error.localizedDescription)
                }

                let isFinal = result?.isFinal ?? false

                if error != nil || isFinal {
                    // Apple SR auto-finalized or errored — but user may still be holding the key
                    // Clean up old recognition task, keep the audio engine running
                    self.recognitionRequest?.endAudio()
                    self.recognitionRequest = nil
                    self.recognitionTask = nil

                    if self.appleUserRequestedStop {
                        // User explicitly released the key — stop everything and paste
                        self.audioEngine?.stop()
                        self.audioEngine?.inputNode.removeTap(onBus: 0)
                        self.audioEngine = nil
                        self.isRecording = false

                        if !self.recognizedText.isEmpty && !self.hasPasted {
                            if self.isSilenceHallucination(self.recognizedText) {
                                NSLog("[SimpleDictation] Suppressed silence hallucination: '%@'", self.recognizedText)
                            } else {
                                self.hasPasted = true
                                self.onTextRecognized?(self.recognizedText)
                            }
                        }
                    } else {
                        // Auto-finalized — save accumulated text and restart recognition
                        let accumulated = self.recognizedText
                        NSLog("[SimpleDictation] Auto-finalized, restarting recognition. Accumulated: %@", accumulated)
                        self.appleAccumulatedText = (self.appleAccumulatedText.isEmpty ? "" : self.appleAccumulatedText + " ") + accumulated
                        self.restartAppleRecognition()
                    }
                }
            }
        }
        pendingRecognitionStart = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: workItem)
    }

    func stopRecording() {
        // Tear down the parallel caption recognizer for every engine path.
        stopCaptionRecognizer()
        if isWhistleEngine { stopWhistleRecording(); return }
        if #available(macOS 14, *) {
            if isMoonshineEngine {
                stopMoonshineRecording()
                return
            }
            if engineMode != "apple" {
                if usingAppleFallback {
                    usingAppleFallback = false
                    stopAppleRecording()
                    return
                }
                stopWhisperRecording()
                return
            }
        }
        stopAppleRecording()
    }

    private func stopAppleRecording() {
        appleUserRequestedStop = true
        pendingRecognitionStart?.cancel()
        pendingRecognitionStart = nil

        // Signal end of audio — this triggers the recognition callback with isFinal
        recognitionRequest?.endAudio()

        // If there's no active recognition task (e.g. between restarts), clean up directly
        if recognitionTask == nil {
            audioEngine?.stop()
            audioEngine?.inputNode.removeTap(onBus: 0)
            audioEngine = nil
            recognitionRequest = nil
            isRecording = false

            let fullText = appleAccumulatedText.isEmpty ? recognizedText :
                (recognizedText.isEmpty ? appleAccumulatedText : appleAccumulatedText + " " + recognizedText)
            if !fullText.isEmpty && !hasPasted {
                if isSilenceHallucination(fullText) {
                    NSLog("[SimpleDictation] Suppressed silence hallucination: '%@'", fullText)
                } else {
                    hasPasted = true
                    recognizedText = fullText
                    onTextRecognized?(fullText)
                }
            }
        }
        // Otherwise the recognition callback will handle cleanup since appleUserRequestedStop is true
    }

    private func stopAppleRecordingInternal() {
        pendingRecognitionStart?.cancel()
        pendingRecognitionStart = nil
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        isRecording = false
    }

    /// Restart Apple recognition on the same audio engine after auto-finalization.
    /// Key fix: keep the existing audio tap running and just swap the recognition request.
    /// The tap always feeds `self.recognitionRequest?.append(buffer)`, so setting a new
    /// request before starting the task means no audio buffers are lost during the gap.
    private func restartAppleRecognition() {
        guard isRecording, let engine = audioEngine, engine.isRunning else {
            NSLog("[SimpleDictation] Cannot restart recognition — engine not running")
            return
        }
        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            NSLog("[SimpleDictation] Cannot restart recognition — recognizer not available")
            return
        }

        recognizedText = ""

        // Create new request and set it BEFORE starting the task.
        // The existing tap closure already does `self?.recognitionRequest?.append(buffer)`,
        // so buffers immediately flow to the new request with no gap.
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        request.contextualStrings = TextPolish.vocabulary
        if #available(macOS 13.0, *) {
            request.addsPunctuation = true
        }
        recognitionRequest = request

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self = self else { return }

            if let result = result {
                self.recognizedText = result.bestTranscription.formattedString
            }
            if let error = error {
                NSLog("[SimpleDictation] Restart recognition error: %@", error.localizedDescription)
            }

            let isFinal = result?.isFinal ?? false
            if error != nil || isFinal {
                self.recognitionRequest?.endAudio()
                self.recognitionRequest = nil
                self.recognitionTask = nil

                if self.appleUserRequestedStop {
                    self.audioEngine?.stop()
                    self.audioEngine?.inputNode.removeTap(onBus: 0)
                    self.audioEngine = nil
                    self.isRecording = false

                    let fullText = self.appleAccumulatedText.isEmpty ? self.recognizedText :
                        (self.recognizedText.isEmpty ? self.appleAccumulatedText : self.appleAccumulatedText + " " + self.recognizedText)
                    if !fullText.isEmpty && !self.hasPasted {
                        if self.isSilenceHallucination(fullText) {
                            NSLog("[SimpleDictation] Suppressed silence hallucination: '%@'", fullText)
                        } else {
                            self.hasPasted = true
                            self.recognizedText = fullText
                            self.onTextRecognized?(fullText)
                        }
                    }
                } else {
                    let accumulated = self.recognizedText
                    NSLog("[SimpleDictation] Auto-finalized again, restarting. Accumulated: %@", accumulated)
                    self.appleAccumulatedText = (self.appleAccumulatedText.isEmpty ? "" : self.appleAccumulatedText + " ") + accumulated
                    self.restartAppleRecognition()
                }
            }
        }

        NSLog("[SimpleDictation] Recognition restarted seamlessly (tap kept running)")
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
        case "whisper-large-v3-turbo": return .largev3Turbo
        case "whisper-large-v3-turbo-632": return .largev3TurboCompressed
        default: return .base
        }
    }

    private var whisperLanguageCode: String {
        return String(currentLocale.prefix(2))
    }

    func preloadWhisperModel() {
        guard #available(macOS 14, *) else { return }
        let model = whisperModel(for: engineMode)
        NSLog("[SimpleDictation] Pre-loading whisper model: %@", model.rawValue)
        Task {
            let _ = await whisperManager.loadModel(model)
        }
    }

    private func startWhisperRecording() {
        hasPasted = false
        recognizedText = ""
        recordingStartTime = Date()
        sampleQueue.sync { whisperSamples = [] }
        whisperPastedCharCount = 0; whisperPastedText = ""
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

    // MARK: - Whistle (Cactus Needle on-device engine)

    private func startWhistleRecording() {
        hasPasted = false
        recognizedText = ""
        recordingStartTime = Date()
        sampleQueue.sync { whisperSamples = [] }
        whisperPastedCharCount = 0; whisperPastedText = ""
        isIncrementalTranscribing = false
        whisperSessionID &+= 1
        stopWhisperRecordingInternal()
        if selectedMicID != 0 { setInputDevice(selectedMicID) }
        // Load whistle.cact (idempotent) off-main, then start the shared 16 kHz capture.
        DispatchQueue.global(qos: .userInitiated).async {
            let ok = self.whistleManager.load()
            DispatchQueue.main.async {
                guard ok else { NSLog("[SimpleDictation] Failed to load Whistle model"); return }
                self.startWhisperAudioCapture()
            }
        }
    }

    private func stopWhistleRecording() {
        whisperTimer?.invalidate()
        whisperTimer = nil
        let hadEngine = audioEngine != nil
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil
        isRecording = false
        guard hadEngine else { return }

        let samples = sampleQueue.sync { whisperSamples }
        guard samples.count > 8000 else {
            NSLog("[SimpleDictation] Whistle: too few samples (%d)", samples.count)
            return
        }

        // If incremental mode already pasted partial text during recording, the
        // final paste must REPLACE it (delete + paste), not append a duplicate.
        let wasIncremental = incrementalActive
        let oldPastedCount = whisperPastedCharCount

        isProcessing = true
        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            guard let self = self else { return }
            let text = self.whistleManager.transcribe(samples: samples, language: nil, keywords: SpeechManager.whistleKeywords)
            DispatchQueue.main.async {
                guard !text.isEmpty, !self.isSilenceHallucination(text) else {
                    self.isProcessing = false
                    return
                }
                self.recognizedText = text
                NSLog("[SimpleDictation] Whistle final: %@", text)
                DispatchQueue.global(qos: .userInteractive).async {
                    if wasIncremental && oldPastedCount > 0 {
                        self.deleteAndPaste(text)
                    } else {
                        self.pasteText(text)
                    }
                    usleep(100000)
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.setString(SpeechManager.cleanTranscript(text), forType: .string)
                    DispatchQueue.main.async { self.isProcessing = false }
                }
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

            // Feed the parallel live-caption recognizer with the raw mic buffer.
            self.feedCaptionBuffer(buffer)

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
                self.sampleQueue.async {
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

        // Stream live captions in parallel (Whisper itself only produces text on stop).
        startCaptionRecognizer()

        // Incremental transcription every 5 seconds (only when incremental mode is on)
        if incrementalActive {
            whisperTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
                self?.performIncrementalTranscription()
            }
        }
    }

    private func performIncrementalTranscription() {
        guard !isIncrementalTranscribing else { return }
        let samples = sampleQueue.sync { whisperSamples }
        guard samples.count > 16000 else { return } // Need at least 1s

        isIncrementalTranscribing = true
        let sessionID = whisperSessionID

        // Whistle is a synchronous, bundled CPU engine — transcribe off-main and
        // route the delta through the same delete-and-replace paste path. Without
        // this branch, incremental would (wrongly) run through WhisperKit, which
        // produces nothing when no Whisper model is downloaded.
        if isWhistleEngine {
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self = self else { return }
                let text = self.whistleManager.transcribe(samples: samples, language: nil, keywords: SpeechManager.whistleKeywords)
                DispatchQueue.main.async {
                    self.isIncrementalTranscribing = false
                    guard self.whisperSessionID == sessionID, self.isRecording, !text.isEmpty else { return }
                    guard !self.isSilenceHallucination(text) else {
                        NSLog("[SimpleDictation] Whistle incremental: suppressed hallucination '%@'", text)
                        return
                    }
                    self.recognizedText = text
                    NSLog("[SimpleDictation] Whistle incremental: %@", text)
                    self.deleteAndPaste(text)
                }
            }
            return
        }

        let langCode = whisperLanguageCode
        Task {
            let text = await whisperManager.transcribe(samples: samples, language: langCode)

            await MainActor.run {
                self.isIncrementalTranscribing = false
                // Discard if this is from a stale session
                guard self.whisperSessionID == sessionID, self.isRecording, !text.isEmpty else { return }

                guard !self.isSilenceHallucination(text) else {
                    NSLog("[SimpleDictation] Whisper incremental: suppressed hallucination '%@'", text)
                    return
                }
                self.recognizedText = text
                NSLog("[SimpleDictation] Whisper incremental: %@", text)

                // Delete old text and replace with full new transcription
                self.deleteAndPaste(text)
            }
        }
    }

    /// Reconcile what's on screen with the new transcript using a DIFF: delete only
    /// the diverging tail, type only the new words (append-only when the transcript
    /// just grows). Fast, and it minimises backspaces — fixing both the "takes
    /// forever" slowdown and the "last segment repastes" duplication.
    private func deleteAndPaste(_ newText: String) {
        let cleaned = SpeechManager.cleanTranscript(newText)
        let target = cleaned.isEmpty ? "" : cleaned + " "
        whisperPastedText = TextInjector.replaceTyped(old: whisperPastedText, new: target)
        whisperPastedCharCount = whisperPastedText.count
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(cleaned, forType: .string)
        fireEnterIfArmed()
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

        let samples = sampleQueue.sync { whisperSamples }
        guard samples.count > 8000 else {
            NSLog("[SimpleDictation] Whisper: too few samples (%d) for transcription", samples.count)
            return
        }

        NSLog("[SimpleDictation] Whisper final transcription: %d samples (%.1fs)", samples.count, Float(samples.count) / 16000.0)

        isProcessing = true
        let langCode = whisperLanguageCode
        let wasIncremental = incrementalActive
        let oldPastedCount = whisperPastedCharCount
        Task {
            let text = await whisperManager.transcribe(samples: samples, language: langCode)

            await MainActor.run {
                guard !text.isEmpty else {
                    self.isProcessing = false
                    return
                }

                if self.isSilenceHallucination(text) {
                    NSLog("[SimpleDictation] Whisper: suppressed silence hallucination: '%@'", text)
                    self.isProcessing = false
                    return
                }

                self.recognizedText = text
                NSLog("[SimpleDictation] Whisper final: %@", text)

                // Paste off main thread so the spinner animation stays smooth
                DispatchQueue.global(qos: .userInteractive).async {
                    if wasIncremental && oldPastedCount > 0 {
                        self.deleteAndPaste(text)
                    } else {
                        self.pasteText(text)
                    }

                    usleep(100000)
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.setString(text, forType: .string)
                    NSLog("[SimpleDictation] Full transcript placed in clipboard (%d chars)", text.count)

                    DispatchQueue.main.async {
                        self.isProcessing = false
                    }
                }
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
        guard #available(macOS 14, *) else { return }
        let model = moonshineModel(for: engineMode)
        NSLog("[SimpleDictation] Pre-loading Moonshine model: %@", model.rawValue)
        Task {
            let _ = await moonshineManager.loadModel(model)
        }
    }

    private func startMoonshineRecording() {
        hasPasted = false
        recognizedText = ""
        recordingStartTime = Date()
        sampleQueue.sync { whisperSamples = [] }
        whisperPastedCharCount = 0; whisperPastedText = ""
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

            // Feed the parallel live-caption recognizer with the raw mic buffer.
            self.feedCaptionBuffer(buffer)

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
                self.sampleQueue.async {
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

        // Stream live captions in parallel (Moonshine only produces text on stop).
        startCaptionRecognizer()

        // Incremental transcription every 5 seconds (only when incremental mode is on)
        if incrementalActive {
            whisperTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
                self?.performMoonshineIncrementalTranscription()
            }
        }
    }

    private func performMoonshineIncrementalTranscription() {
        guard !isIncrementalTranscribing else { return }
        let samples = sampleQueue.sync { whisperSamples }
        guard samples.count > 16000 else { return }

        isIncrementalTranscribing = true
        let sessionID = whisperSessionID
        Task {
            let text = await moonshineManager.transcribe(samples: samples)

            await MainActor.run {
                self.isIncrementalTranscribing = false
                guard self.whisperSessionID == sessionID, self.isRecording, !text.isEmpty else { return }

                guard !self.isSilenceHallucination(text) else {
                    NSLog("[SimpleDictation] Moonshine incremental: suppressed hallucination '%@'", text)
                    return
                }
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

        let samples = sampleQueue.sync { whisperSamples }
        guard samples.count > 8000 else {
            NSLog("[SimpleDictation] Moonshine: too few samples (%d) for transcription", samples.count)
            return
        }

        NSLog("[SimpleDictation] Moonshine final transcription: %d samples (%.1fs)", samples.count, Float(samples.count) / 16000.0)

        isProcessing = true
        let wasIncremental = incrementalActive
        let oldPastedCount = whisperPastedCharCount
        Task {
            let text = await moonshineManager.transcribe(samples: samples)

            await MainActor.run {
                guard !text.isEmpty else {
                    self.isProcessing = false
                    return
                }

                if self.isSilenceHallucination(text) {
                    NSLog("[SimpleDictation] Moonshine: suppressed silence hallucination: '%@'", text)
                    self.isProcessing = false
                    return
                }

                self.recognizedText = text
                NSLog("[SimpleDictation] Moonshine final: %@", text)

                // Paste off main thread so the spinner animation stays smooth
                DispatchQueue.global(qos: .userInteractive).async {
                    if wasIncremental && oldPastedCount > 0 {
                        self.deleteAndPaste(text)
                    } else {
                        self.pasteText(text)
                    }

                    usleep(100000)
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.setString(text, forType: .string)
                    NSLog("[SimpleDictation] Full transcript placed in clipboard (%d chars)", text.count)

                    DispatchQueue.main.async {
                        self.isProcessing = false
                    }
                }
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

    // "Send" gesture support: Return must land after the dictated text, which
    // is typed asynchronously once transcription finishes.
    private var enterArmedUntil: Date?
    private let enterLock = NSLock()

    /// Press Return once the dictation now finishing has been typed. If nothing
    /// gets typed within `seconds`, nothing is pressed.
    func pressEnterAfterDelivery(within seconds: TimeInterval = 10) {
        enterLock.lock(); enterArmedUntil = Date().addingTimeInterval(seconds); enterLock.unlock()
    }

    func cancelPendingEnter() {
        enterLock.lock(); enterArmedUntil = nil; enterLock.unlock()
    }

    /// Return now, or after the text if a transcription is still in flight.
    func sendReturn() {
        if isProcessing { pressEnterAfterDelivery() } else { pressEnter() }
    }

    private func fireEnterIfArmed() {
        enterLock.lock()
        let armed = enterArmedUntil.map { $0 > Date() } ?? false
        enterArmedUntil = nil
        enterLock.unlock()
        guard armed else { return }
        // Give the app a beat to take in the typed characters first.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in self?.pressEnter() }
    }

    func pressEnter() {
        // Use privateState so modifiers (fn/option) held by the user
        // don't turn this into Option+Return (newline) instead of Return (submit)
        let src = CGEventSource(stateID: .privateState)
        let down = CGEvent(keyboardEventSource: src, virtualKey: 36, keyDown: true)
        down?.flags = []  // Clear all modifier flags
        down?.post(tap: .cghidEventTap)
        let up = CGEvent(keyboardEventSource: src, virtualKey: 36, keyDown: false)
        up?.flags = []
        up?.post(tap: .cghidEventTap)
    }

    /// Custom-dictionary words as Whistle expects them: newline-separated, or nil.
    static var whistleKeywords: String? {
        let words = TextPolish.vocabulary
        return words.isEmpty ? nil : words.joined(separator: "\n")
    }

    // MARK: - Paste

    /// Strip non-speech annotation tokens that Whisper/Apple emit as literal text
    /// — e.g. "[BLANK_AUDIO]", "[coughing]", "(upbeat music)", "♪", arrows — so
    /// they never get pasted or shown. Returns the cleaned, whitespace-collapsed
    /// string; empty means "nothing worth pasting." Idempotent.
    static func cleanTranscript(_ text: String) -> String {
        var s = text
        // Anything wrapped in [ ], ( ), or < > is a sound/scene annotation.
        for pattern in ["\\[[^\\]]*\\]", "\\([^\\)]*\\)", "<[^>]*>"] {
            s = s.replacingOccurrences(of: pattern, with: " ", options: .regularExpression)
        }
        // Musical-note and arrow glyphs that captioning models sprinkle in.
        s = s.replacingOccurrences(of: "[♪♫♬➤➜→⟶►◄«»]", with: " ", options: .regularExpression)
        // Collapse the whitespace the removals leave behind.
        s = s.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        // Whisper/Whistle emit "Thank you." / "Thanks for watching" / "Bye" on
        // trailing silence (a YouTube-caption training artifact). Peel one such
        // trailer off the END when a real sentence precedes it — but never strip a
        // short, genuinely-meant "thank you".
        let trailer = "[,\\.\\s]+(thank you(\\s+for\\s+watching| very much)?|thanks(\\s+for\\s+watching)?|bye(\\s+bye)?|you)[\\.\\!\\s]*$"
        if let re = try? NSRegularExpression(pattern: trailer, options: [.caseInsensitive]),
           let m = re.firstMatch(in: s, options: [], range: NSRange(s.startIndex..<s.endIndex, in: s)),
           let r = Range(m.range, in: s) {
            let before = String(s[s.startIndex..<r.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            if before.count >= 12 { s = before }
        }
        // Filler removal and the user's custom dictionary (both on-device rules).
        return TextPolish.apply(s)
    }

    func pasteText(_ text: String) {
        let cleaned = SpeechManager.cleanTranscript(text)
        guard !cleaned.isEmpty else {
            slog("pasteText: nothing to paste after stripping annotations from '\(text)'")
            return
        }
        // Optional on-device language-model pass (Apple Intelligence). Only for a
        // finished transcript: paste-as-you-speak has already typed the words.
        if AIPolish.enabled, !incrementalActive, AIPolish.isAvailable {
            Task { [weak self] in
                let polished = await AIPolish.polish(cleaned) ?? cleaned
                await MainActor.run { self?.deliver(polished) }
            }
            return
        }
        deliver(cleaned)
    }

    private func deliver(_ cleaned: String) {
        // Type the text directly via CGEventKeyboardSetUnicodeString instead of a
        // synthetic Cmd+V. Verified (injection test) to be reliable even while a
        // trigger key is physically held, and it doesn't drop in Chrome/Electron the
        // way paste does. Keep the transcript on the clipboard too for manual re-paste.
        TextInjector.typeUnicode(cleaned + " ", pid: nil)
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(cleaned, forType: .string)
        fireEnterIfArmed()
    }
}
