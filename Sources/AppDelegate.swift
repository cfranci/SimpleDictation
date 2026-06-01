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
    
    /// Set of enabled modifier keys. Any one triggers recording.
    /// Stored in UserDefaults as an array of strings.
    static let allModifierKeys = ["fn", "control", "option", "command"]
    static let defaultEnabledModifiers: Set<String> = ["fn", "option"]

    var enabledModifiers: Set<String> {
        get {
            if let saved = UserDefaults.standard.array(forKey: "enabledModifiers") as? [String] {
                return Set(saved)
            }
            return AppDelegate.defaultEnabledModifiers
        }
        set {
            UserDefaults.standard.set(Array(newValue), forKey: "enabledModifiers")
        }
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

        speechManager?.engineMode = "apple"  // Ventura build: Apple Speech only

        speechManager?.onRecordingStateChanged = { [weak self] recording in
            self?.statusBarController?.isRecording = recording
            self?.floatingWindow?.updateAppearance(recording: recording)
        }

        speechManager?.onProcessingStateChanged = { [weak self] processing in
            self?.floatingWindow?.updateProcessing(processing)
        }

        statusBarController = StatusBarController(speechManager: speechManager!)
        statusBarController?.onModifiersChanged = { [weak self] (modifiers: Set<String>) in
            self?.enabledModifiers = modifiers
        }
        statusBarController?.onEngineChanged = { [weak self] (engine: String) in
            self?.currentEngine = engine
            self?.speechManager?.engineMode = engine
            self?.floatingWindow?.updateEngineLabel(engine)
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
        statusBarController?.enabledModifiers = enabledModifiers
        statusBarController?.currentEngine = currentEngine
        statusBarController?.onSizeChanged = { [weak self] size in
            self?.floatingWindow?.updateSize(size)
        }

        // Floating mic window — always visible fallback for menu bar
        let savedIconSize = CGFloat(UserDefaults.standard.object(forKey: "floatingMicSize") as? Int ?? 40)
        floatingWindow = FloatingMicWindow(
            speechManager: speechManager!,
            circleSize: savedIconSize,
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
                guard let window = view.window, let screen = window.screen ?? NSScreen.main else {
                    menu.popUp(positioning: nil, at: NSPoint(x: 0, y: view.bounds.height + 5), in: view)
                    return
                }

                let menuSize = menu.size
                let viewFrameInScreen = window.convertToScreen(view.convert(view.bounds, to: nil))
                let sf = screen.visibleFrame

                // Decide whether to open upward or downward
                let spaceAbove = sf.maxY - viewFrameInScreen.maxY
                let spaceBelow = viewFrameInScreen.minY - sf.minY
                let openUpward = spaceBelow > spaceAbove || spaceAbove < menuSize.height

                // Horizontal: prefer left-aligned, shift left if it overflows
                var x = viewFrameInScreen.minX
                if x + menuSize.width > sf.maxX {
                    x = viewFrameInScreen.maxX - menuSize.width
                }
                x = max(x, sf.minX)

                // popUp(positioning:) places the chosen menu item at the given point.
                // positioning: nil = top of menu at the point (opens downward).
                // positioning: lastItem = bottom of menu at the point (opens upward).
                let positionItem: NSMenuItem?
                let y: CGFloat
                if openUpward {
                    // Anchor the last menu item at the top of the view
                    positionItem = menu.items.last
                    y = viewFrameInScreen.maxY + 5
                } else {
                    // Anchor the top of the menu at the top of the view
                    positionItem = nil
                    y = viewFrameInScreen.maxY + 5
                }

                let windowPoint = window.convertFromScreen(NSRect(origin: NSPoint(x: x, y: y), size: .zero)).origin
                let viewPoint = view.convert(windowPoint, from: nil)
                menu.popUp(positioning: positionItem, at: viewPoint, in: view)
            }
        )

        speechManager?.checkAuthorization()

        let trusted = AXIsProcessTrusted()
        NSLog("[SimpleDictation] Accessibility trusted: %d", trusted)
        if !trusted {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
            AXIsProcessTrustedWithOptions(options)
        }

        setupGlobalHotkeyMonitor()
        setupLocalHotkeyMonitor()
        setupClipboardCycler()

        // Set dock icon from bundled .icns
        if let iconPath = Bundle.main.path(forResource: "AppIcon", ofType: "icns"),
           let icon = NSImage(contentsOfFile: iconPath) {
            NSApp.applicationIconImage = icon
        }

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

        let flags = event.modifierFlags
        let modifiers = enabledModifiers

        // Check if ANY enabled modifier is currently held
        var isHotkeyActive = false
        if modifiers.contains("fn") && flags.contains(.function) { isHotkeyActive = true }
        if modifiers.contains("control") && flags.contains(.control) { isHotkeyActive = true }
        if modifiers.contains("option") && flags.contains(.option) { isHotkeyActive = true }
        if modifiers.contains("command") && flags.contains(.command) { isHotkeyActive = true }

        NSLog("[SimpleDictation] isHotkeyActive=%d isRecording=%d modifiers=%@", isHotkeyActive, speechManager.isRecording, modifiers.joined(separator: ","))
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

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // When user double-clicks the app while it's already running as an accessory,
        // show the status bar menu instead of hanging with "not responding"
        if let button = statusBarController?.statusItem?.button {
            button.performClick(nil)
        }
        return false
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
