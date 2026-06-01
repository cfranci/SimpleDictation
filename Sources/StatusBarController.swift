import Cocoa
import Combine

class StatusBarController: NSObject {
    private(set) var statusItem: NSStatusItem!
    private(set) var menu: NSMenu!
    private var speechManager: SpeechManager
    private var cancellables = Set<AnyCancellable>()
    var clipboardHistory: [String] = []
    private var clipboardTimer: Timer?
    private var lastChangeCount: Int = 0
    private let maxHistory = 10
    var suppressClipboardMonitoring = false
    private let previewLength = 40

    // Mouse interaction tracking
    private var lastClickTime: Date = Date.distantPast
    private var lastRightClickTime: Date = Date.distantPast
    private var isMouseRecording: Bool = false
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var globalRightClickMonitor: Any?

    // Callbacks for AppDelegate to wire up
    var onStartRecording: (() -> Void)?
    var onStopRecording: (() -> Void)?
    var onEnterPressed: (() -> Void)?

    var onModifiersChanged: ((Set<String>) -> Void)?
    var onEngineChanged: ((String) -> Void)?
    var enabledModifiers: Set<String> = ["fn", "option"] {
        didSet {
            updateHotkeyMenu()
        }
    }

    var currentEngine: String = "apple" {
        didSet {
            updateEngineMenu()
        }
    }

    var isEnabled: Bool = true {
        didSet {
            updateStatusIcon()
            updateEnabledMenu()
        }
    }

    var onEnabledChanged: ((Bool) -> Void)?

    var isRecording: Bool = false {
        didSet {
            updateStatusIcon()
        }
    }
    
    init(speechManager: SpeechManager) {
        self.speechManager = speechManager
        super.init()
        setupStatusItem()
        setupMenu()
        observeSpeechManager()
        startClipboardMonitor()
    }
    
    private func setupStatusItem() {
        // Remove any existing status item first
        if let old = statusItem {
            NSStatusBar.system.removeStatusItem(old)
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.isVisible = true

        if let button = statusItem.button {
            button.title = ""
            button.image = NSImage(systemSymbolName: "mic.circle", accessibilityDescription: "SimpleDictation")
            button.image?.isTemplate = true
            button.imagePosition = .imageOnly
            button.toolTip = "Simple Dictation"
        }

        NSLog("[SimpleDictation] Status item created, button=%@, frame=%@",
              statusItem.button != nil ? "YES" : "NO",
              statusItem.button?.window != nil ? "has window" : "NO window")
    }

    /// Force-recreate the status item (useful when macOS drops it from crowded menu bars)
    func recreateStatusItem() {
        NSLog("[SimpleDictation] Recreating status item")
        setupStatusItem()
        if let button = statusItem.button {
            button.action = #selector(statusBarButtonClicked(_:))
            button.target = self
        }
        updateStatusIcon()
        setupMouseHandling()
    }
    
    private func createCircleImage(filled: Bool) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            let circlePath = NSBezierPath(ovalIn: rect.insetBy(dx: 3, dy: 3))
            if filled {
                NSColor.black.setFill()
                circlePath.fill()
            } else {
                NSColor.black.setStroke()
                circlePath.lineWidth = 1.5
                circlePath.stroke()
            }
            return true
        }
        image.isTemplate = !filled
        return image
    }

    private func createRecordingImage() -> NSImage {
        guard let symbol = NSImage(systemSymbolName: "mic.circle.fill", accessibilityDescription: "Recording") else {
            return NSImage()
        }
        let config = NSImage.SymbolConfiguration(hierarchicalColor: NSColor.red.withAlphaComponent(0.15))
        let result = symbol.withSymbolConfiguration(config) ?? symbol
        result.isTemplate = false
        return result
    }

    private func updateStatusIcon() {
        if let button = statusItem.button {
            if !isEnabled {
                button.image = NSImage(systemSymbolName: "minus.circle", accessibilityDescription: "Disabled")
                button.image?.isTemplate = true
            } else if isRecording {
                button.image = createRecordingImage()
            } else {
                button.image = NSImage(systemSymbolName: "mic.circle", accessibilityDescription: "SimpleDictation")
                button.image?.isTemplate = true
            }
        }
    }

    private func createDashImage() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.black.setStroke()
            let path = NSBezierPath()
            path.lineWidth = 2.0
            path.move(to: NSPoint(x: 4, y: rect.midY))
            path.line(to: NSPoint(x: 14, y: rect.midY))
            path.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }
    
    private func setupMenu() {
        menu = NSMenu()
        
        let titleItem = NSMenuItem(title: "Simple Dictation", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let statusTitle = speechManager.isAuthorized ? "Ready" : "Not Authorized"
        let statusItem = NSMenuItem(title: "Status: \(statusTitle)", action: nil, keyEquivalent: "")
        statusItem.isEnabled = false
        statusItem.tag = 100
        menu.addItem(statusItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let hotkeyHeader = NSMenuItem(title: "Trigger Modifiers:", action: nil, keyEquivalent: "")
        hotkeyHeader.isEnabled = false
        menu.addItem(hotkeyHeader)

        let fnItem = NSMenuItem(title: "Fn", action: #selector(toggleModifier(_:)), keyEquivalent: "")
        fnItem.target = self
        fnItem.tag = 1
        fnItem.representedObject = "fn" as NSString
        menu.addItem(fnItem)

        let ctrlItem = NSMenuItem(title: "Control", action: #selector(toggleModifier(_:)), keyEquivalent: "")
        ctrlItem.target = self
        ctrlItem.tag = 2
        ctrlItem.representedObject = "control" as NSString
        menu.addItem(ctrlItem)

        let optionItem = NSMenuItem(title: "Option", action: #selector(toggleModifier(_:)), keyEquivalent: "")
        optionItem.target = self
        optionItem.tag = 3
        optionItem.representedObject = "option" as NSString
        menu.addItem(optionItem)

        let cmdItem = NSMenuItem(title: "Command", action: #selector(toggleModifier(_:)), keyEquivalent: "")
        cmdItem.target = self
        cmdItem.tag = 4
        cmdItem.representedObject = "command" as NSString
        menu.addItem(cmdItem)
        
        menu.addItem(NSMenuItem.separator())

        let micHeader = NSMenuItem(title: "Microphone:", action: nil, keyEquivalent: "")
        micHeader.isEnabled = false
        menu.addItem(micHeader)

        let micSubmenu = NSMenu()
        let micItem = NSMenuItem(title: "Select Mic", action: nil, keyEquivalent: "")
        micItem.tag = 400
        micItem.submenu = micSubmenu
        menu.addItem(micItem)
        updateMicMenu()

        menu.addItem(NSMenuItem.separator())

        let langHeader = NSMenuItem(title: "Language:", action: nil, keyEquivalent: "")
        langHeader.isEnabled = false
        menu.addItem(langHeader)

        let langSubmenu = NSMenu()
        let langItem = NSMenuItem(title: "English (US)", action: nil, keyEquivalent: "")
        langItem.tag = 500
        langItem.submenu = langSubmenu
        menu.addItem(langItem)
        updateLanguageMenu()

        menu.addItem(NSMenuItem.separator())

        let engineHeader = NSMenuItem(title: "Engine:", action: nil, keyEquivalent: "")
        engineHeader.isEnabled = false
        menu.addItem(engineHeader)

        let appleItem = NSMenuItem(title: "Apple Speech", action: #selector(setEngine(_:)), keyEquivalent: "")
        appleItem.target = self
        appleItem.tag = 601
        appleItem.state = .on
        menu.addItem(appleItem)

        // Ventura build: Apple Speech is the only engine. WhisperKit/Moonshine
        // (macOS 14+ only) are not bundled in this fork.

        menu.addItem(NSMenuItem.separator())

        let incrementalItem = NSMenuItem(title: "Incremental Mode", action: #selector(toggleIncrementalMode), keyEquivalent: "")
        incrementalItem.target = self
        incrementalItem.tag = 700
        incrementalItem.state = speechManager.incrementalMode ? .on : .off
        menu.addItem(incrementalItem)

        let sizeSubmenu = NSMenu()
        let savedSize = UserDefaults.standard.object(forKey: "floatingMicSize") as? Int ?? 40
        for size in stride(from: 10, through: 50, by: 10) {
            let item = NSMenuItem(title: "\(size)px", action: #selector(setIconSize(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = size as NSNumber
            item.state = size == savedSize ? .on : .off
            sizeSubmenu.addItem(item)
        }
        let sizeItem = NSMenuItem(title: "Icon Size: \(savedSize)px", action: nil, keyEquivalent: "")
        sizeItem.tag = 899
        sizeItem.submenu = sizeSubmenu
        menu.addItem(sizeItem)

        menu.addItem(NSMenuItem.separator())

        let toggleItem = NSMenuItem(title: "Turn Off", action: #selector(toggleEnabled), keyEquivalent: "")
        toggleItem.target = self
        toggleItem.tag = 200
        menu.addItem(toggleItem)

        menu.addItem(NSMenuItem.separator())

        let cycleItem = NSMenuItem(title: "Clipboard Cycling (Cmd+V×2)", action: #selector(toggleClipboardCycling), keyEquivalent: "")
        cycleItem.target = self
        cycleItem.tag = 800
        cycleItem.state = UserDefaults.standard.bool(forKey: "clipboardCyclingEnabled") ? .on : .off
        menu.addItem(cycleItem)

        menu.addItem(NSMenuItem.separator())

        let clipHeader = NSMenuItem(title: "Clipboard History:", action: nil, keyEquivalent: "")
        clipHeader.isEnabled = false
        clipHeader.tag = 300
        menu.addItem(clipHeader)

        let emptyItem = NSMenuItem(title: "  (empty)", action: nil, keyEquivalent: "")
        emptyItem.isEnabled = false
        emptyItem.tag = 301
        menu.addItem(emptyItem)

        menu.addItem(NSMenuItem.separator())

        let authItem = NSMenuItem(title: "Request Permissions...", action: #selector(requestPermissions), keyEquivalent: "")
        authItem.target = self
        menu.addItem(authItem)

        let resetBarItem = NSMenuItem(title: "Reset Menu Bar Icon", action: #selector(resetMenuBarIcon), keyEquivalent: "")
        resetBarItem.target = self
        menu.addItem(resetBarItem)

        menu.addItem(NSMenuItem.separator())

        let restartItem = NSMenuItem(title: "Restart", action: #selector(restartApp), keyEquivalent: "r")
        restartItem.target = self
        menu.addItem(restartItem)

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        updateHotkeyMenu()
        updateEngineMenu()

        // Don't assign menu to statusItem — we handle clicks manually
        setupMouseHandling()
    }
    
    private func updateHotkeyMenu() {
        for item in menu.items where (1...4).contains(item.tag) {
            if let key = item.representedObject as? String {
                item.state = enabledModifiers.contains(key) ? .on : .off
            }
        }
    }

    @objc private func toggleModifier(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String else { return }
        var mods = enabledModifiers
        if mods.contains(key) {
            // Don't allow disabling the last modifier
            if mods.count > 1 {
                mods.remove(key)
            }
        } else {
            mods.insert(key)
        }
        enabledModifiers = mods
        onModifiersChanged?(enabledModifiers)
    }
    
    func updateMicMenu() {
        speechManager.refreshMicList()
        guard let micItem = menu.item(withTag: 400), let submenu = micItem.submenu else { return }
        submenu.removeAllItems()

        let mics = speechManager.availableMics
        if mics.isEmpty {
            let noMic = NSMenuItem(title: "No microphones found", action: nil, keyEquivalent: "")
            noMic.isEnabled = false
            submenu.addItem(noMic)
        } else {
            for mic in mics {
                let item = NSMenuItem(title: mic.name, action: #selector(selectMic(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = mic.id as NSNumber
                item.state = mic.id == speechManager.selectedMicID ? .on : .off
                submenu.addItem(item)
            }
        }

        if let selected = mics.first(where: { $0.id == speechManager.selectedMicID }) {
            micItem.title = selected.name
        } else if let first = mics.first {
            micItem.title = first.name
        } else {
            micItem.title = "No Mic"
        }
    }

    @objc private func selectMic(_ sender: NSMenuItem) {
        guard let deviceID = sender.representedObject as? NSNumber else { return }
        speechManager.selectMic(deviceID.uint32Value)
        updateMicMenu()
    }

    private func updateLanguageMenu() {
        guard let langItem = menu.item(withTag: 500), let submenu = langItem.submenu else { return }
        submenu.removeAllItems()

        for locale in SpeechManager.supportedLocales {
            let item = NSMenuItem(title: locale.name, action: #selector(selectLanguage(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = locale.id
            item.state = locale.id == speechManager.currentLocale ? .on : .off
            submenu.addItem(item)
        }

        if let current = SpeechManager.supportedLocales.first(where: { $0.id == speechManager.currentLocale }) {
            langItem.title = current.name
        }
    }

    @objc private func selectLanguage(_ sender: NSMenuItem) {
        guard let localeID = sender.representedObject as? String else { return }
        speechManager.setLocale(localeID)
        UserDefaults.standard.set(localeID, forKey: "dictationLocale")
        updateLanguageMenu()
    }

    @objc private func setEngine(_ sender: NSMenuItem) {
        // Ventura build: Apple Speech is the only engine.
        currentEngine = "apple"
        onEngineChanged?(currentEngine)
    }

    private func updateEngineMenu() {
        // Only the Apple Speech engine exists in this fork.
        menu.item(withTag: 601)?.state = .on
    }

    @objc private func toggleEnabled() {
        isEnabled = !isEnabled
        onEnabledChanged?(isEnabled)
    }

    var onIncrementalChanged: ((Bool) -> Void)?
    var onSizeChanged: ((CGFloat) -> Void)?

    @objc private func toggleIncrementalMode() {
        speechManager.incrementalMode = !speechManager.incrementalMode
        if let item = menu.item(withTag: 700) {
            item.state = speechManager.incrementalMode ? .on : .off
        }
        onIncrementalChanged?(speechManager.incrementalMode)
    }

    @objc private func setIconSize(_ sender: NSMenuItem) {
        guard let size = sender.representedObject as? NSNumber else { return }
        UserDefaults.standard.set(size.intValue, forKey: "floatingMicSize")
        if let sizeItem = menu.item(withTag: 899), let submenu = sizeItem.submenu {
            for item in submenu.items {
                if let s = item.representedObject as? NSNumber {
                    item.state = s.intValue == size.intValue ? .on : .off
                }
            }
            sizeItem.title = "Icon Size: \(size.intValue)px"
        }
        onSizeChanged?(CGFloat(size.intValue))
    }

    private func updateEnabledMenu() {
        if let item = menu.item(withTag: 200) {
            item.title = isEnabled ? "Turn Off" : "Turn On"
        }
        if let statusItem = menu.item(withTag: 100) {
            if !isEnabled {
                statusItem.title = "Status: Off"
            } else {
                let statusTitle = speechManager.isAuthorized ? "Ready" : "Not Authorized"
                statusItem.title = "Status: \(statusTitle)"
            }
        }
    }

    private func startClipboardMonitor() {
        let pb = NSPasteboard.general
        lastChangeCount = pb.changeCount
        if let text = pb.string(forType: .string), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            clipboardHistory.insert(text.trimmingCharacters(in: .whitespacesAndNewlines), at: 0)
            updateClipboardMenu()
        }
        clipboardTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.checkClipboard()
        }
    }

    func syncClipboardChangeCount() {
        lastChangeCount = NSPasteboard.general.changeCount
    }

    private func checkClipboard() {
        let pb = NSPasteboard.general
        let current = pb.changeCount
        guard current != lastChangeCount else { return }
        lastChangeCount = current

        guard !suppressClipboardMonitoring else { return }

        guard let text = pb.string(forType: .string), !text.isEmpty else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if clipboardHistory.first == trimmed { return }
        clipboardHistory.removeAll { $0 == trimmed }
        clipboardHistory.insert(trimmed, at: 0)
        if clipboardHistory.count > maxHistory {
            clipboardHistory = Array(clipboardHistory.prefix(maxHistory))
        }
        updateClipboardMenu()
    }

    private func clipboardPreview(_ text: String) -> String {
        let oneLine = text.components(separatedBy: .newlines).joined(separator: " ")
        if oneLine.count <= previewLength { return oneLine }
        return String(oneLine.prefix(previewLength)) + "..."
    }

    private func updateClipboardMenu() {
        guard let headerIndex = menu.items.firstIndex(where: { $0.tag == 300 }) else { return }

        // Remove old clipboard items (tags 301-305)
        menu.items.filter { $0.tag >= 301 && $0.tag <= 310 }.forEach { menu.removeItem($0) }

        if clipboardHistory.isEmpty {
            let emptyItem = NSMenuItem(title: "  (empty)", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            emptyItem.tag = 301
            menu.insertItem(emptyItem, at: headerIndex + 1)
        } else {
            for (i, text) in clipboardHistory.enumerated() {
                let item = NSMenuItem(title: "  \(clipboardPreview(text))", action: #selector(clipboardItemClicked(_:)), keyEquivalent: "")
                item.target = self
                item.tag = 301 + i
                item.representedObject = text
                menu.insertItem(item, at: headerIndex + 1 + i)
            }
        }
    }

    @objc private func clipboardItemClicked(_ sender: NSMenuItem) {
        guard let text = sender.representedObject as? String else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        lastChangeCount = pb.changeCount
    }

    @objc private func requestPermissions() {
        speechManager.checkAuthorization()
    }

    @objc private func resetMenuBarIcon() {
        recreateStatusItem()
    }

    var onClipboardCyclingChanged: ((Bool) -> Void)?

    @objc private func toggleClipboardCycling() {
        let current = UserDefaults.standard.bool(forKey: "clipboardCyclingEnabled")
        let newValue = !current
        UserDefaults.standard.set(newValue, forKey: "clipboardCyclingEnabled")
        if let item = menu.item(withTag: 800) {
            item.state = newValue ? .on : .off
        }
        onClipboardCyclingChanged?(newValue)
    }
    
    @objc private func restartApp() {
        let bundlePath = Bundle.main.bundlePath
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 1 && open \"\(bundlePath)\""]
        try? task.run()
        NSApp.terminate(nil)
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
    
    private func observeSpeechManager() {
        speechManager.$isAuthorized
            .receive(on: DispatchQueue.main)
            .sink { [weak self] authorized in
                guard let self = self else { return }
                if let statusItem = self.menu.item(withTag: 100) {
                    statusItem.title = "Status: \(authorized ? "Ready" : "Not Authorized")"
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Debug Log

    func debugLog(_ msg: String) {
        let line = "\(Date()): \(msg)\n"
        NSLog("[SimpleDictation] %@", msg)
        let path = "/tmp/simpledictation.log"
        if let handle = FileHandle(forWritingAtPath: path) {
            handle.seekToEndOfFile()
            handle.write(line.data(using: .utf8)!)
            handle.closeFile()
        } else {
            FileManager.default.createFile(atPath: path, contents: line.data(using: .utf8))
        }
    }

    // MARK: - Mouse Handling

    private func setupMouseHandling() {
        guard let button = statusItem.button else { return }

        // Use button action for left click — properly ends status bar tracking
        button.action = #selector(statusBarButtonClicked(_:))
        button.target = self

        // Local monitor for right-click on status bar icon → show menu
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown]) { [weak self] event in
            guard let self = self else { return event }
            guard let btn = self.statusItem.button, event.window == btn.window else { return event }
            self.debugLog("Right-click on status bar, showing menu")
            self.menu.popUp(positioning: nil, at: NSPoint(x: 0, y: btn.bounds.height + 5), in: btn)
            return nil
        }

        // Global monitor: left-click in other apps stops recording; right-click for double-right-click → Enter
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self = self else { return }

            if event.type == .rightMouseDown {
                let now = Date()
                if now.timeIntervalSince(self.lastRightClickTime) < 0.4 {
                    self.debugLog("Double right-click detected, pressing Enter")
                    self.lastRightClickTime = Date.distantPast
                    self.onEnterPressed?()
                } else {
                    self.lastRightClickTime = now
                }
                return
            }

            // Left mouse down
            guard self.isMouseRecording else { return }
            self.debugLog("Click outside detected, will stop recording in 0.5s")
            self.isMouseRecording = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.debugLog("Firing onStopRecording")
                self.onStopRecording?()
            }
        }

        debugLog("Mouse handling setup complete")
    }

    @objc private func statusBarButtonClicked(_ sender: Any?) {
        debugLog("statusBarButtonClicked fired")
        handleStatusBarClick()
    }

    private func handleStatusBarClick() {
        guard isEnabled else {
            debugLog("handleStatusBarClick: not enabled")
            return
        }

        if isMouseRecording {
            debugLog("Status bar click: stopping recording")
            isMouseRecording = false
            onStopRecording?()

            // Check for double-click → Enter
            let now = Date()
            if now.timeIntervalSince(lastClickTime) < 0.4 {
                debugLog("Double-click detected, pressing Enter")
                lastClickTime = Date.distantPast
                onEnterPressed?()
            } else {
                lastClickTime = now
            }
        } else {
            // Not recording → check double-click first, otherwise start recording
            let now = Date()
            if now.timeIntervalSince(lastClickTime) < 0.4 {
                debugLog("Double-click detected, pressing Enter")
                lastClickTime = Date.distantPast
                onEnterPressed?()
                return
            }

            debugLog("Status bar click: starting recording")
            lastClickTime = now
            isMouseRecording = true
            onStartRecording?()
        }
    }

    deinit {
        if let monitor = globalMouseMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let monitor = localMouseMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}
