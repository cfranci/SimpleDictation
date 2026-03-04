import Cocoa
import Combine

class StatusBarController: NSObject {
    private var statusItem: NSStatusItem!
    private var menu: NSMenu!
    private var speechManager: SpeechManager
    private var cancellables = Set<AnyCancellable>()
    private var clipboardHistory: [String] = []
    private var clipboardTimer: Timer?
    private var lastChangeCount: Int = 0
    private let maxHistory = 5
    private let previewLength = 40
    private var pulseTimer: Timer?
    private var pulseOpacity: CGFloat = 1.0
    private var pulseIncreasing: Bool = false

    var onHotkeyChanged: ((String) -> Void)?
    var onEngineChanged: ((String) -> Void)?
    var currentHotkey: String = "fn" {
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
            if isRecording {
                startPulseAnimation()
            } else {
                stopPulseAnimation()
            }
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
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        
        if let button = statusItem.button {
            button.image = createCircleImage(filled: false)
            button.image?.isTemplate = true
        }
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

    private func createRecordingImage(opacity: CGFloat) -> NSImage {
        let size = NSSize(width: 36, height: 36)
        let image = NSImage(size: size, flipped: false) { rect in
            let color = NSColor.red.withAlphaComponent(opacity)
            color.setFill()
            let circlePath = NSBezierPath(ovalIn: rect.insetBy(dx: 4, dy: 4))
            circlePath.fill()
            return true
        }
        image.isTemplate = false
        return image
    }

    private func updateStatusIcon() {
        if let button = statusItem.button {
            if !isEnabled {
                button.image = createDashImage()
                button.image?.isTemplate = true
            } else if isRecording {
                button.image = createRecordingImage(opacity: pulseOpacity)
            } else {
                button.image = createCircleImage(filled: false)
                button.image?.isTemplate = true
            }
        }
    }

    private func startPulseAnimation() {
        pulseOpacity = 1.0
        pulseIncreasing = false
        pulseTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self = self, self.isRecording else { return }
            if self.pulseIncreasing {
                self.pulseOpacity += 0.03
                if self.pulseOpacity >= 1.0 {
                    self.pulseOpacity = 1.0
                    self.pulseIncreasing = false
                }
            } else {
                self.pulseOpacity -= 0.03
                if self.pulseOpacity <= 0.4 {
                    self.pulseOpacity = 0.4
                    self.pulseIncreasing = true
                }
            }
            if let button = self.statusItem.button {
                button.image = self.createRecordingImage(opacity: self.pulseOpacity)
            }
        }
    }

    private func stopPulseAnimation() {
        pulseTimer?.invalidate()
        pulseTimer = nil
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
        
        let hotkeyHeader = NSMenuItem(title: "Hotkey:", action: nil, keyEquivalent: "")
        hotkeyHeader.isEnabled = false
        menu.addItem(hotkeyHeader)
        
        let fnItem = NSMenuItem(title: "Fn", action: #selector(setHotkey(_:)), keyEquivalent: "")
        fnItem.target = self
        fnItem.tag = 1
        menu.addItem(fnItem)
        
        let optionItem = NSMenuItem(title: "Option", action: #selector(setHotkey(_:)), keyEquivalent: "")
        optionItem.target = self
        optionItem.tag = 2
        menu.addItem(optionItem)
        
        let bothItem = NSMenuItem(title: "Fn or Option", action: #selector(setHotkey(_:)), keyEquivalent: "")
        bothItem.target = self
        bothItem.tag = 3
        menu.addItem(bothItem)
        
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
        menu.addItem(appleItem)

        let whisperTinyItem = NSMenuItem(title: "Whisper Tiny (~40MB)", action: #selector(setEngine(_:)), keyEquivalent: "")
        whisperTinyItem.target = self
        whisperTinyItem.tag = 602
        menu.addItem(whisperTinyItem)

        let whisperBaseItem = NSMenuItem(title: "Whisper Base (~140MB)", action: #selector(setEngine(_:)), keyEquivalent: "")
        whisperBaseItem.target = self
        whisperBaseItem.tag = 603
        menu.addItem(whisperBaseItem)

        let whisperSmallItem = NSMenuItem(title: "Whisper Small (~460MB)", action: #selector(setEngine(_:)), keyEquivalent: "")
        whisperSmallItem.target = self
        whisperSmallItem.tag = 604
        menu.addItem(whisperSmallItem)

        let whisperMediumItem = NSMenuItem(title: "Whisper Medium (~1.5GB)", action: #selector(setEngine(_:)), keyEquivalent: "")
        whisperMediumItem.target = self
        whisperMediumItem.tag = 605
        menu.addItem(whisperMediumItem)

        menu.addItem(NSMenuItem.separator())

        let toggleItem = NSMenuItem(title: "Turn Off", action: #selector(toggleEnabled), keyEquivalent: "")
        toggleItem.target = self
        toggleItem.tag = 200
        menu.addItem(toggleItem)

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
        
        menu.addItem(NSMenuItem.separator())
        
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        updateHotkeyMenu()
        updateEngineMenu()

        self.statusItem.menu = menu
    }
    
    private func updateHotkeyMenu() {
        for item in menu.items {
            if item.tag == 1 {  // Fn
                item.state = currentHotkey == "fn" ? .on : .off
            } else if item.tag == 2 {  // Option
                item.state = currentHotkey == "option" ? .on : .off
            } else if item.tag == 3 {  // Both
                item.state = currentHotkey == "both" ? .on : .off
            }
        }
    }
    
    @objc private func setHotkey(_ sender: NSMenuItem) {
        switch sender.tag {
        case 1:
            currentHotkey = "fn"
        case 2:
            currentHotkey = "option"
        case 3:
            currentHotkey = "both"
        default:
            break
        }
        onHotkeyChanged?(currentHotkey)
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
        switch sender.tag {
        case 601:
            currentEngine = "apple"
        case 602:
            currentEngine = "whisper-tiny"
        case 603:
            currentEngine = "whisper-base"
        case 604:
            currentEngine = "whisper-small"
        case 605:
            currentEngine = "whisper-medium"
        default:
            break
        }
        onEngineChanged?(currentEngine)
    }

    private func updateEngineMenu() {
        let engineMap: [(tag: Int, mode: String)] = [
            (601, "apple"),
            (602, "whisper-tiny"),
            (603, "whisper-base"),
            (604, "whisper-small"),
            (605, "whisper-medium"),
        ]
        for entry in engineMap {
            if let item = menu.item(withTag: entry.tag) {
                item.state = currentEngine == entry.mode ? .on : .off
            }
        }
    }

    @objc private func toggleEnabled() {
        isEnabled = !isEnabled
        onEnabledChanged?(isEnabled)
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

    private func checkClipboard() {
        let pb = NSPasteboard.general
        let current = pb.changeCount
        guard current != lastChangeCount else { return }
        lastChangeCount = current

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
        menu.items.filter { $0.tag >= 301 && $0.tag <= 305 }.forEach { menu.removeItem($0) }

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
}
