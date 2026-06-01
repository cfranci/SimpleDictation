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
    // Ventura build: Apple Speech is the only engine. Kept for menu/UI plumbing compatibility.
    @Published var engineMode: String = "apple"

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

    // Guard against overlapping Apple recognition starts
    private var pendingRecognitionStart: DispatchWorkItem?
    private var appleUserRequestedStop: Bool = false
    private var appleAccumulatedText: String = ""

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
        // Ventura build: Apple Speech only.
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
        // Ventura build: Apple Speech only.
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

    // MARK: - Keypress Helpers

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
