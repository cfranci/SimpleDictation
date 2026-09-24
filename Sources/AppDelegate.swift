import Cocoa
import Speech
import Combine
import QuartzCore

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusBarController: StatusBarController?
    var speechManager: SpeechManager?
    var floatingWindow: FloatingMicWindow?
    var clipboardCycler: ClipboardCycler?
    var eventMonitor: Any?
    var localMonitor: Any?
    var triggerWatcher: TriggerWatcher?
    var lastKeyRelease: Date = Date.distantPast
    private var cancellables = Set<AnyCancellable>()
    
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
            // Solidify the caption: this text is finalized by the engine.
            CaptionOverlayController.shared.update(text, final: true)
        }

        speechManager?.engineMode = currentEngine

        // Model download/loading notifications (macOS 14+ only)
        if #available(macOS 14, *) {
            speechManager?.whisperManager.onModelLoading = { [weak self] (isLoading, model, success) in
                guard let self = self else { return }
                if isLoading {
                    self.showModelNotification("Downloading \(model.displayName)...")
                    self.statusBarController?.startDownloadFlash(forEngine: model.rawValue)
                    self.floatingWindow?.updateDownloading(true)
                } else {
                    self.statusBarController?.stopDownloadFlash()
                    self.floatingWindow?.updateDownloading(false)
                    if success {
                        self.showModelNotification("✓ \(model.displayName) ready", autoDismiss: true)
                    } else {
                        self.showModelNotification("✗ \(model.displayName) failed", autoDismiss: true)
                    }
                }
            }
        }

        speechManager?.onFallbackToApple = { [weak self] modelName in
            self?.showModelNotification("Using Apple Speech while \(modelName) downloads...")
        }

        speechManager?.onRecordingStateChanged = { [weak self] recording in
            self?.statusBarController?.isRecording = recording
            self?.floatingWindow?.updateAppearance(recording: recording)
            // Pause media / mute sound while dictating, restore when done.
            if recording {
                MediaController.shared.recordingStarted()
                CaptionOverlayController.shared.begin()
            } else {
                MediaController.shared.recordingStopped()
                CaptionOverlayController.shared.end()
            }
        }

        // Live caption overlay: mirror recognized text as it's spoken. For the
        // Apple engine this streams word-by-word; for Whisper/Moonshine it also
        // fires with the final transcript once it lands.
        speechManager?.$recognizedText
            .receive(on: DispatchQueue.main)
            .sink { text in
                CaptionOverlayController.shared.update(text)
            }
            .store(in: &cancellables)

        // Live captions for Whisper/Moonshine come from the parallel Apple
        // recognizer (those engines only produce their own text on stop).
        speechManager?.onCaptionText = { text, isFinal in
            CaptionOverlayController.shared.update(text, final: isFinal)
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
        setupExternalTrigger()

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
    
    /// External trigger: another app (e.g. AAA) writes a command to the trigger
    /// file and we drive the same recording code path as the hotkey.
    func setupExternalTrigger() {
        triggerWatcher = TriggerWatcher { [weak self] cmd in
            self?.handleExternalCommand(cmd)
        }
        NSLog("[SimpleDictation] External trigger watching %@", TriggerWatcher.defaultPath)
    }

    func handleExternalCommand(_ cmd: String) {
        guard let speechManager = speechManager, let statusBarController = statusBarController else { return }
        guard statusBarController.isEnabled else { return }

        switch cmd {
        case "start":
            if speechManager.isRecording { return }
            // Double-tap detection: a fresh start right after a stop sends Enter
            if Date().timeIntervalSince(lastKeyRelease) < 0.4 {
                NSLog("[SimpleDictation] External: double-tap, pressing Enter")
                speechManager.pressEnter()
                return
            }
            NSLog("[SimpleDictation] External: starting recording")
            speechManager.startRecording()
            statusBarController.isRecording = speechManager.isRecording
            floatingWindow?.updateAppearance(recording: speechManager.isRecording)
        case "stop":
            if !speechManager.isRecording { return }
            NSLog("[SimpleDictation] External: stopping recording")
            lastKeyRelease = Date()
            speechManager.stopRecording()
            statusBarController.isRecording = false
            floatingWindow?.updateAppearance(recording: false)
        case "toggle":
            handleExternalCommand(speechManager.isRecording ? "stop" : "start")
        case "enter":
            NSLog("[SimpleDictation] External: pressing Enter")
            speechManager.pressEnter()
        case "captiontest":
            NSLog("[SimpleDictation] External: caption test")
            runCaptionTest()
        default:
            NSLog("[SimpleDictation] External: unknown command '%@'", cmd)
        }
    }

    /// Synthetic streaming caption for verifying the overlay without speaking:
    /// streams a long sentence word-by-word (so it overflows and the left edge
    /// fades), solidifies, then fades out — the exact live code path.
    func runCaptionTest() {
        let cap = CaptionOverlayController.shared
        cap.begin()
        let words = ("This is a live caption streaming test to verify the overlay appears while "
            + "speaking grows to the right hard block and old words dissolve softly off the left "
            + "edge before fading away over one second").split(separator: " ").map(String.init)
        var acc = ""
        let step = 0.18
        for (i, w) in words.enumerated() {
            acc = acc.isEmpty ? w : acc + " " + w
            let snapshot = acc
            DispatchQueue.main.asyncAfter(deadline: .now() + step * Double(i)) {
                cap.update(snapshot, final: false)
            }
        }
        let total = step * Double(words.count)
        DispatchQueue.main.asyncAfter(deadline: .now() + total + 0.1) {
            cap.update(acc, final: true)   // solidify the last word
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + total + 0.7) {
            cap.end()                      // key-release → 1s fade-out
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
        // Make sure we never leave the system muted if we quit mid-dictation.
        MediaController.shared.recordingStopped()
    }
}

// MARK: - Media Controller

/// Pauses media (or mutes the whole system) while dictation is active and
/// restores it when dictation ends. Driven from the recording-state hook so it
/// fires no matter how recording was started — hotkey, menu-bar/floating mic
/// click, or an external trigger.
final class MediaController {
    static let shared = MediaController()

    enum Method: String {
        case pauseApps   // pause running media players (Music, Spotify, …)
        case muteSystem  // mute all system audio output
    }

    /// Players offered in the menu by default. Only apps that expose the
    /// standard `player state` / `play` / `pause` AppleScript verbs can be
    /// paused precisely; anything else is best handled by "Mute All Sound".
    static let commonApps = ["Music", "Spotify", "TV", "Podcasts"]
    static let defaultApps = ["Music", "Spotify", "TV", "Podcasts"]

    private let enabledKey = "pauseMediaEnabled"
    private let methodKey  = "pauseMediaMethod"
    private let appsKey    = "pauseMediaApps"

    /// Serial queue so AppleScript runs off the main thread and never blocks
    /// the moment recording starts/stops.
    private let queue = DispatchQueue(label: "com.simpledictation.mediacontroller")

    // Restore state (only touched on `queue`).
    private var pausedApps: [String] = []
    private var restoreUnmute = false

    var enabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    var method: Method {
        get { Method(rawValue: UserDefaults.standard.string(forKey: methodKey) ?? "") ?? .pauseApps }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: methodKey) }
    }

    var apps: [String] {
        get { UserDefaults.standard.array(forKey: appsKey) as? [String] ?? MediaController.defaultApps }
        set { UserDefaults.standard.set(newValue, forKey: appsKey) }
    }

    func recordingStarted() {
        guard enabled else { return }
        let method = self.method
        let apps = self.apps
        queue.async { [weak self] in
            switch method {
            case .pauseApps:  self?.pauseApps(apps)
            case .muteSystem: self?.muteSystem()
            }
        }
    }

    func recordingStopped() {
        // Always run on stop so a half-open state can't leave media paused /
        // the system muted, even if the setting was toggled mid-session.
        let method = self.method
        queue.async { [weak self] in
            switch method {
            case .pauseApps:  self?.resumeApps()
            case .muteSystem: self?.unmuteSystem()
            }
        }
    }

    // MARK: Pause / resume media players

    private func pauseApps(_ apps: [String]) {
        pausedApps = []
        for app in apps {
            let script = """
            if application "\(app)" is running then
              tell application "\(app)"
                try
                  if player state is playing then
                    pause
                    return "paused"
                  end if
                end try
              end tell
            end if
            return "no"
            """
            if runScript(script) == "paused" {
                pausedApps.append(app)
            }
        }
    }

    private func resumeApps() {
        for app in pausedApps {
            _ = runScript("""
            if application "\(app)" is running then
              tell application "\(app)" to play
            end if
            """)
        }
        pausedApps = []
    }

    // MARK: Mute / unmute the whole system

    private func muteSystem() {
        // Don't unmute later if the user was already muted before dictating.
        let wasMuted = runScript("""
        if output muted of (get volume settings) then
          return "true"
        else
          return "false"
        end if
        """) == "true"
        restoreUnmute = !wasMuted
        if restoreUnmute {
            _ = runScript("set volume output muted true")
        }
    }

    private func unmuteSystem() {
        if restoreUnmute {
            _ = runScript("set volume output muted false")
        }
        restoreUnmute = false
    }

    // MARK: AppleScript helper

    @discardableResult
    private func runScript(_ source: String) -> String? {
        guard let script = NSAppleScript(source: source) else { return nil }
        var err: NSDictionary?
        let result = script.executeAndReturnError(&err)
        if let err = err {
            NSLog("[SimpleDictation] MediaController AppleScript error: %@", err)
            return nil
        }
        return result.stringValue
    }
}

// MARK: - Live Caption Overlay

/// A borderless, click-through caption bar that shows the recognized text live
/// as you speak. It appears only on the display that currently contains the
/// mouse cursor, and its size, edge (top/bottom) and alignment (left/center/
/// right) are all user-configurable.
final class CaptionOverlayController {
    static let shared = CaptionOverlayController()

    private enum FadeMode { case none, fadingIn, fadingOut }

    private var panel: NSPanel?
    private var textClip: NSView?
    private var label: NSTextField?
    private var fadeMaskLayer: CAGradientLayer?
    private var hideTimer: Timer?
    private var fadeTimer: Timer?
    private var activeScreen: NSScreen?
    private var fadeMode: FadeMode = .none
    private var sessionShown = false
    private var recordingActive = false
    private var currentText = ""
    private var currentFinal = false

    private let hPad: CGFloat = 7         // box hugs the text — only a few px wider
    private let vPad: CGFloat = 4
    private let corner: CGFloat = 6
    private let sideMargin: CGFloat = 8   // hard right/left block inset from screen edge
    private let edgeMargin: CGFloat = 3   // distance from the top/bottom of the screen

    private let enabledKey    = "captionEnabled"
    private let fontSizeKey   = "captionFontSize"
    private let positionKey   = "captionPosition"    // "top" | "bottom"
    private let alignmentKey  = "captionAlignment"   // "left" | "center" | "right"
    private let backgroundKey = "captionBackground"  // Bool — draw the pill or not
    private let opacityKey    = "captionOpacity"     // Double 0…1 — pill translucency

    var enabled: Bool {
        get { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: enabledKey)
            if newValue { preview() } else { onMain { self.hideNow() } }
        }
    }

    var fontSize: CGFloat {
        get { CGFloat(UserDefaults.standard.object(forKey: fontSizeKey) as? Int ?? 32) }
        set {
            UserDefaults.standard.set(Int(newValue), forKey: fontSizeKey)
            onMain { self.applyStyle(); self.reposition() }
        }
    }

    var position: String {
        get { UserDefaults.standard.string(forKey: positionKey) ?? "bottom" }
        set {
            UserDefaults.standard.set(newValue, forKey: positionKey)
            onMain { self.reposition() }
        }
    }

    var alignment: String {
        get { UserDefaults.standard.string(forKey: alignmentKey) ?? "center" }
        set {
            UserDefaults.standard.set(newValue, forKey: alignmentKey)
            onMain { self.applyStyle(); self.reposition() }
        }
    }

    var showBackground: Bool {
        get { UserDefaults.standard.object(forKey: backgroundKey) as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: backgroundKey)
            onMain { self.applyBackground() }
        }
    }

    /// Opacity of the pill background, 0 (fully clear) … 1 (solid).
    var backgroundOpacity: Double {
        get { UserDefaults.standard.object(forKey: opacityKey) as? Double ?? 0.3 }
        set {
            UserDefaults.standard.set(newValue, forKey: opacityKey)
            onMain { self.applyBackground() }
        }
    }

    /// Called when dictation starts — lock onto the cursor's screen, but don't
    /// show anything until the first words actually arrive.
    func begin() {
        guard enabled else { return }
        onMain {
            self.cancelTimers()
            self.fadeMode = .none
            self.sessionShown = false
            self.recordingActive = true
            self.ensurePanel()
            self.applyBackground()
            self.panel?.alphaValue = 1.0
            self.activeScreen = self.screenWithCursor() ?? NSScreen.main
            self.setText("", final: false)
            self.panel?.orderOut(nil)
        }
    }

    /// Live recognized text as it's spoken. `final` = the engine has committed it.
    /// Text can arrive DURING recording (Apple, streamed word-by-word) or AFTER
    /// the key is released (Whisper/Moonshine, transcribed on stop) — both work.
    func update(_ text: String, final: Bool = false) {
        guard enabled else { return }
        guard !text.isEmpty else { return }
        onMain {
            // New text cancels any in-progress fade-out so it's shown solidly.
            if self.fadeMode == .fadingOut {
                self.fadeTimer?.invalidate(); self.fadeTimer = nil
                self.fadeMode = .none
                self.panel?.alphaValue = 1.0
            }
            self.hideTimer?.invalidate(); self.hideTimer = nil
            self.ensurePanel()
            if self.activeScreen == nil { self.activeScreen = self.screenWithCursor() ?? NSScreen.main }
            self.setText(text, final: final)
            self.reposition()

            if !self.sessionShown {
                self.sessionShown = true
                self.startFadeIn(duration: 0.2)
            } else if self.fadeMode == .none {
                self.panel?.alphaValue = 1.0
                self.panel?.orderFrontRegardless()
            }

            // If the key was already released, this is trailing text (e.g. a
            // Whisper transcript landing after stop): hold briefly, then fade.
            if !self.recordingActive {
                self.armHide(delay: 1.0)
            }
        }
    }

    /// Called when the key is released. If the caption is already on screen
    /// (live text), fade it out now over one second. If nothing is showing yet
    /// (Whisper still transcribing), a trailing update() will show-then-fade it.
    func end() {
        onMain {
            self.recordingActive = false
            guard let panel = self.panel, panel.isVisible, self.fadeMode != .fadingOut else { return }
            self.armHide(delay: 0.0)
        }
    }

    /// Briefly show sample text so settings changes are visible without dictating.
    func preview() {
        guard enabled else { return }
        onMain {
            self.cancelTimers()
            self.fadeMode = .none
            self.sessionShown = true
            self.recordingActive = false
            self.ensurePanel()
            self.applyBackground()
            self.activeScreen = self.screenWithCursor() ?? NSScreen.main
            self.setText("Live caption preview", final: true)
            self.reposition()
            self.startFadeIn(duration: 0.2)
            // Hold for a moment, then demo the same one-second fade-out.
            self.hideTimer = Timer.scheduledTimer(withTimeInterval: 1.3, repeats: false) { [weak self] _ in
                self?.startFadeOut(duration: 1.0)
            }
        }
    }

    // MARK: - Internals

    private func cancelTimers() {
        hideTimer?.invalidate(); hideTimer = nil
        fadeTimer?.invalidate(); fadeTimer = nil
    }

    /// Schedule the fade-out: immediately (delay 0) or after a short hold.
    private func armHide(delay: TimeInterval) {
        hideTimer?.invalidate(); hideTimer = nil
        if delay <= 0 {
            startFadeOut(duration: 1.0)
        } else {
            hideTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
                self?.startFadeOut(duration: 1.0)
            }
        }
    }

    /// Fade the panel's opacity from 0 to 1 over `duration` as it appears.
    private func startFadeIn(duration: TimeInterval) {
        guard let panel = panel else { return }
        fadeTimer?.invalidate()
        fadeMode = .fadingIn
        panel.alphaValue = 0.0
        panel.orderFrontRegardless()
        let steps = 12
        let interval = max(0.01, duration / Double(steps))
        var current = 0
        fadeTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] t in
            guard let self = self, let panel = self.panel else { t.invalidate(); return }
            current += 1
            panel.alphaValue = min(1.0, CGFloat(current) / CGFloat(steps))
            if current >= steps {
                t.invalidate()
                self.fadeTimer = nil
                self.fadeMode = .none
                panel.alphaValue = 1.0
            }
        }
    }

    /// Fade the panel's opacity to zero over `duration`, then hide and reset.
    private func startFadeOut(duration: TimeInterval) {
        guard let panel = panel else { return }
        fadeTimer?.invalidate()
        fadeMode = .fadingOut
        let steps = 30
        let interval = max(0.01, duration / Double(steps))
        let startAlpha = panel.alphaValue
        var current = 0
        fadeTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] t in
            guard let self = self, let panel = self.panel else { t.invalidate(); return }
            current += 1
            let progress = CGFloat(current) / CGFloat(steps)
            panel.alphaValue = startAlpha * (1 - progress)
            if current >= steps {
                t.invalidate()
                self.fadeTimer = nil
                self.fadeMode = .none
                self.sessionShown = false
                panel.orderOut(nil)
                panel.alphaValue = 1.0
            }
        }
    }

    private func hideNow() {
        cancelTimers()
        fadeMode = .none
        sessionShown = false
        panel?.orderOut(nil)
        panel?.alphaValue = 1.0
    }

    private func onMain(_ block: @escaping () -> Void) {
        if Thread.isMainThread { block() } else { DispatchQueue.main.async(execute: block) }
    }

    private func screenWithCursor() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
    }

    private func ensurePanel() {
        if panel != nil { return }
        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 80),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.level = .floating
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.ignoresMouseEvents = true
        p.isFloatingPanel = true
        p.hidesOnDeactivate = false
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]

        // Pill background (rounded, solid — stays crisp).
        let bg = NSView()
        bg.wantsLayer = true
        bg.layer?.cornerRadius = corner
        bg.layer?.masksToBounds = true

        // Transparent clip that holds the text and carries the left-edge fade
        // mask, so only the TEXT dissolves on the left, not the pill itself.
        let clip = NSView()
        clip.wantsLayer = true
        clip.layer?.masksToBounds = true

        let lbl = NSTextField(labelWithString: "")
        lbl.isEditable = false
        lbl.isBordered = false
        lbl.drawsBackground = false
        lbl.isSelectable = false
        lbl.usesSingleLineMode = true
        lbl.maximumNumberOfLines = 1
        lbl.lineBreakMode = .byClipping   // never wrap, never ellipsize — just clip
        lbl.cell?.wraps = false
        lbl.cell?.isScrollable = true
        lbl.textColor = .white

        clip.addSubview(lbl)
        bg.addSubview(clip)
        p.contentView = bg
        self.panel = p
        self.textClip = clip
        self.label = lbl
        applyStyle()
        applyBackground()
    }

    private func applyBackground() {
        guard let bg = panel?.contentView else { return }
        let alpha = showBackground ? CGFloat(backgroundOpacity) : 0.0
        bg.layer?.backgroundColor = NSColor(white: 0.0, alpha: alpha).cgColor
    }

    private func applyStyle() {
        guard let lbl = label else { return }
        // Text is positioned manually (right-anchored) in reposition(), so the
        // label's own alignment is left within its exact-fit frame.
        lbl.alignment = .left
        // Rebuild attributed text so font-size / setting changes restyle live.
        renderText()
    }

    private func setText(_ text: String, final: Bool) {
        currentText = text
        currentFinal = final
        renderText()
    }

    /// White + shadow text, every word fully solid (no dimming) — words simply
    /// appear one after another as they're recognized, like VNOCH.
    private func renderText() {
        guard let lbl = label else { return }
        let font = NSFont.systemFont(ofSize: fontSize, weight: .semibold)

        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.95)
        shadow.shadowBlurRadius = 4
        shadow.shadowOffset = NSSize(width: 0, height: -1)

        lbl.attributedStringValue = NSAttributedString(string: currentText, attributes: [
            .font: font, .foregroundColor: NSColor.white, .shadow: shadow,
        ])
    }

    private func reposition() {
        guard let panel = panel, let lbl = label, let clip = textClip, let bg = panel.contentView else { return }
        guard let screen = activeScreen ?? screenWithCursor() ?? NSScreen.main ?? NSScreen.screens.first else { return }
        let vf = screen.visibleFrame

        // The pill can grow until it spans (almost) the whole screen width. That
        // right edge is the "hard block": once reached, the bar stops widening
        // and new words push the older text off the left edge (single line).
        let maxWidth = max(120, vf.width - sideMargin * 2)

        // Measure the full, single-line text width (unbounded — never wraps).
        let unbounded = CGFloat.greatestFiniteMagnitude
        let full = lbl.sizeThatFits(NSSize(width: unbounded, height: unbounded))
        let textW: CGFloat = ceil(full.width)
        let textH: CGFloat = ceil(full.height)

        let panelW = min(textW + hPad * 2, maxWidth)
        let panelH = textH + vPad * 2
        let innerW = panelW - hPad * 2

        // Right-anchor the text: its right edge sits at the inner right padding;
        // when the text is wider than the pill, labelX goes negative and the
        // left of the text runs off the edge.
        let labelX = hPad + (innerW - textW)
        lbl.frame = NSRect(x: labelX, y: vPad, width: textW, height: textH)

        // Horizontal placement. "center" starts centered and expands outward
        // until it hits the hard block; "left"/"right" pin to that edge.
        var x: CGFloat
        switch alignment {
        case "left":  x = vf.minX + sideMargin
        case "right": x = vf.maxX - sideMargin - panelW
        default:      x = vf.midX - panelW / 2
        }
        x = max(vf.minX + sideMargin, min(x, vf.maxX - sideMargin - panelW))

        // Vertical placement — a few px from the chosen edge.
        let y: CGFloat = (position == "top")
            ? vf.maxY - edgeMargin - panelH
            : vf.minY + edgeMargin

        panel.setFrame(NSRect(x: x, y: y, width: panelW, height: panelH), display: true)

        // Layer geometry changes without implicit animations (avoid flicker).
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        bg.frame = NSRect(x: 0, y: 0, width: panelW, height: panelH)
        clip.frame = NSRect(x: 0, y: 0, width: panelW, height: panelH)

        // Soft gradient fade on the left edge — only when text overflows, so
        // words dissolve into transparency as they scroll off instead of a
        // hard cut.
        let overflow = textW > innerW + 0.5
        if overflow {
            let fadeWidth = min(max(fontSize * 1.8, 36), panelW * 0.35)
            let frac = max(0.02, min(0.6, fadeWidth / panelW))
            let mask = fadeMaskLayer ?? CAGradientLayer()
            mask.startPoint = CGPoint(x: 0, y: 0.5)
            mask.endPoint = CGPoint(x: 1, y: 0.5)
            mask.colors = [
                NSColor(white: 1, alpha: 0).cgColor,
                NSColor(white: 1, alpha: 1).cgColor,
                NSColor(white: 1, alpha: 1).cgColor,
            ]
            mask.locations = [0.0, NSNumber(value: Double(frac)), 1.0]
            mask.frame = CGRect(x: 0, y: 0, width: panelW, height: panelH)
            fadeMaskLayer = mask
            clip.layer?.mask = mask
        } else {
            clip.layer?.mask = nil
        }
        CATransaction.commit()
    }
}
