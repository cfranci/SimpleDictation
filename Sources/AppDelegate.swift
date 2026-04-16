import Cocoa
import Speech

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusBarController: StatusBarController?
    var speechManager: SpeechManager?
    var floatingWindow: FloatingMicWindow?
    var clipboardCycler: ClipboardCycler?
    var eventMonitor: Any?
    var localMonitor: Any?
    var lastKeyRelease: Date = Date.distantPast
    
    let hotkeyOptions = ["fn", "option", "both"]
    var currentHotkey: String {
        get { UserDefaults.standard.string(forKey: "dictationHotkey") ?? "fn" }
        set { UserDefaults.standard.set(newValue, forKey: "dictationHotkey") }
    }
    var currentEngine: String {
        get { UserDefaults.standard.string(forKey: "dictationEngine") ?? "apple" }
        set { UserDefaults.standard.set(newValue, forKey: "dictationEngine") }
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        speechManager = SpeechManager()
        if let savedLocale = UserDefaults.standard.string(forKey: "dictationLocale") {
            speechManager?.setLocale(savedLocale)
        }
        speechManager?.onTextRecognized = { [weak self] (text: String) in
            self?.speechManager?.pasteText(text)
        }

        speechManager?.engineMode = currentEngine

        // Model download/loading notifications (macOS 14+ only)
        if #available(macOS 14, *) {
            speechManager?.whisperManager.onModelLoading = { [weak self] (isLoading, model, success) in
                guard let self = self else { return }
                if isLoading {
                    self.showModelNotification("Downloading \(model.displayName)...")
                    self.statusBarController?.startDownloadFlash(forEngine: model.rawValue)
                } else {
                    self.statusBarController?.stopDownloadFlash()
                    if success {
                        self.showModelNotification("✓ \(model.displayName) ready", autoDismiss: true)
                    } else {
                        self.showModelNotification("✗ \(model.displayName) failed", autoDismiss: true)
                    }
                }
            }
        }

        statusBarController = StatusBarController(speechManager: speechManager!)
        statusBarController?.onHotkeyChanged = { [weak self] (hotkey: String) in
            self?.currentHotkey = hotkey
        }
        statusBarController?.onEngineChanged = { [weak self] (engine: String) in
            self?.currentEngine = engine
            self?.speechManager?.engineMode = engine
            self?.floatingWindow?.updateEngineLabel(engine)
            if engine.hasPrefix("moonshine-") {
                self?.speechManager?.preloadMoonshineModel()
            } else if engine != "apple" {
                self?.speechManager?.preloadWhisperModel()
            }
        }
        statusBarController?.onEnabledChanged = { [weak self] (enabled: Bool) in
            if !enabled {
                self?.speechManager?.stopRecording()
                self?.statusBarController?.isRecording = false
            }
        }
        statusBarController?.onStartRecording = { [weak self] in
            guard let self = self, let sm = self.speechManager, let sbc = self.statusBarController else { return }
            guard sbc.isEnabled else { return }
            NSLog("[SimpleDictation] Mouse: starting recording")
            sm.startRecording()
            sbc.isRecording = sm.isRecording
        }
        statusBarController?.onStopRecording = { [weak self] in
            guard let self = self, let sm = self.speechManager, let sbc = self.statusBarController else { return }
            self.statusBarController?.debugLog("onStopRecording: text='\(sm.recognizedText)'")
            self.lastKeyRelease = Date()
            // Just stop recording — let the recognition callback handle paste
            // via onTextRecognized, same code path as the working hotkey flow
            sm.stopRecording()
            sbc.isRecording = false
        }
        statusBarController?.onEnterPressed = { [weak self] in
            NSLog("[SimpleDictation] Mouse: pressing Enter")
            self?.speechManager?.pressEnter()
        }
        statusBarController?.onIncrementalChanged = { (enabled: Bool) in
            UserDefaults.standard.set(enabled, forKey: "incrementalMode")
        }
        speechManager?.incrementalMode = UserDefaults.standard.bool(forKey: "incrementalMode")
        statusBarController?.currentHotkey = currentHotkey
        statusBarController?.currentEngine = currentEngine

        // Floating mic window — always visible fallback for menu bar
        floatingWindow = FloatingMicWindow(
            speechManager: speechManager!,
            onToggleRecording: { [weak self] in
                guard let self = self, let sm = self.speechManager else { return }
                if sm.isRecording {
                    self.lastKeyRelease = Date()
                    sm.stopRecording()
                    self.statusBarController?.isRecording = false
                    self.floatingWindow?.updateAppearance(recording: false)
                } else {
                    sm.startRecording()
                    self.statusBarController?.isRecording = sm.isRecording
                    self.floatingWindow?.updateAppearance(recording: sm.isRecording)
                }
            },
            onEnterPressed: { [weak self] in
                self?.speechManager?.pressEnter()
            },
            onRightClick: { [weak self] view in
                guard let self = self, let menu = self.statusBarController?.menu else { return }
                menu.popUp(positioning: nil, at: NSPoint(x: 0, y: view.bounds.height + 5), in: view)
            }
        )

        speechManager?.checkAuthorization()
        if currentEngine.hasPrefix("moonshine-") {
            speechManager?.preloadMoonshineModel()
        } else if currentEngine != "apple" {
            speechManager?.preloadWhisperModel()
        }

        let trusted = AXIsProcessTrusted()
        NSLog("[SimpleDictation] Accessibility trusted: %d", trusted)
        if !trusted {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
            AXIsProcessTrustedWithOptions(options)
        }

        setupGlobalHotkeyMonitor()
        setupLocalHotkeyMonitor()
        setupClipboardCycler()

        NSApp.setActivationPolicy(.accessory)
    }
    
    func setupGlobalHotkeyMonitor() {
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleHotkeyEvent(event)
        }
    }
    
    func setupLocalHotkeyMonitor() {
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleHotkeyEvent(event)
            return event
        }
    }
    
    func handleHotkeyEvent(_ event: NSEvent) {
        guard let speechManager = speechManager, let statusBarController = statusBarController else { return }
        guard statusBarController.isEnabled else { return }
        NSLog("[SimpleDictation] Hotkey event: fn=%d option=%d", event.modifierFlags.contains(.function), event.modifierFlags.contains(.option))

        let hotkey = currentHotkey
        let isFn = event.modifierFlags.contains(.function)
        let isOption = event.modifierFlags.contains(.option)
        
        let isHotkeyActive: Bool
        switch hotkey {
        case "fn": isHotkeyActive = isFn
        case "option": isHotkeyActive = isOption
        case "both": isHotkeyActive = isFn || isOption
        default: isHotkeyActive = isFn
        }
        
        NSLog("[SimpleDictation] isHotkeyActive=%d isRecording=%d hotkey=%@", isHotkeyActive, speechManager.isRecording, hotkey)
        if isHotkeyActive != speechManager.isRecording {
            if isHotkeyActive {
                // Double-tap detection: if last release was < 400ms ago, send Enter instead
                if Date().timeIntervalSince(lastKeyRelease) < 0.4 {
                    NSLog("[SimpleDictation] Double-tap detected, pressing Enter")
                    speechManager.pressEnter()
                    return
                }
                NSLog("[SimpleDictation] Starting recording...")
                speechManager.startRecording()
                statusBarController.isRecording = speechManager.isRecording
                floatingWindow?.updateAppearance(recording: speechManager.isRecording)
                NSLog("[SimpleDictation] After startRecording, isRecording=%d", speechManager.isRecording)
            } else {
                NSLog("[SimpleDictation] Stopping recording...")
                lastKeyRelease = Date()
                speechManager.stopRecording()
                statusBarController.isRecording = false
                floatingWindow?.updateAppearance(recording: false)
            }
        }
    }
    
    func setupClipboardCycler() {
        let cycler = ClipboardCycler()
        cycler.getClipboardHistory = { [weak self] in
            return self?.statusBarController?.clipboardHistory ?? []
        }
        cycler.onCyclingStateChanged = { [weak self] isCycling in
            self?.statusBarController?.suppressClipboardMonitoring = isCycling
            if !isCycling {
                self?.statusBarController?.syncClipboardChangeCount()
            }
        }
        cycler.enabled = UserDefaults.standard.bool(forKey: "clipboardCyclingEnabled")
        cycler.start()
        clipboardCycler = cycler

        statusBarController?.onClipboardCyclingChanged = { [weak self] enabled in
            self?.clipboardCycler?.enabled = enabled
        }
    }

    // MARK: - Model download notification

    private var notificationWindow: NSPanel?
    private var notificationDismissTimer: Timer?

    func showModelNotification(_ message: String, autoDismiss: Bool = false) {
        notificationDismissTimer?.invalidate()

        if let existing = notificationWindow {
            // Update existing notification
            if let label = existing.contentView?.subviews.first as? NSTextField {
                label.stringValue = message
            }
        } else {
            // Create floating notification near the mic window
            let width: CGFloat = 220
            let height: CGFloat = 36

            let screen = NSScreen.main ?? NSScreen.screens.first!
            let micFrame = floatingWindow?.frame ?? NSRect(x: screen.frame.maxX - 60, y: screen.frame.maxY - 80, width: 44, height: 58)
            let x = micFrame.minX - width - 8
            let y = micFrame.midY - height / 2

            let panel = NSPanel(
                contentRect: NSRect(x: x, y: y, width: width, height: height),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.level = .floating
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.collectionBehavior = [.canJoinAllSpaces, .stationary]
            panel.hidesOnDeactivate = false

            let bg = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))
            bg.wantsLayer = true
            bg.layer?.backgroundColor = NSColor(white: 0.12, alpha: 0.92).cgColor
            bg.layer?.cornerRadius = 10

            let label = NSTextField(labelWithString: message)
            label.font = NSFont.systemFont(ofSize: 12, weight: .medium)
            label.textColor = .white
            label.alignment = .center
            label.frame = NSRect(x: 8, y: 0, width: width - 16, height: height)
            bg.addSubview(label)

            panel.contentView = bg
            panel.orderFrontRegardless()
            notificationWindow = panel
        }

        if autoDismiss {
            notificationDismissTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] _ in
                self?.notificationWindow?.orderOut(nil)
                self?.notificationWindow = nil
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}
