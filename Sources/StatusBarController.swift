import Cocoa
import Combine
import UniformTypeIdentifiers

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
        menu.addItem(appleItem)

        // Whisper & Moonshine engines — macOS 14+ only
        if #available(macOS 14, *) {
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

            let distilV3Item = NSMenuItem(title: "Distil-Whisper Large v3 (~594MB)", action: #selector(setEngine(_:)), keyEquivalent: "")
            distilV3Item.target = self
            distilV3Item.tag = 606
            menu.addItem(distilV3Item)

            let distilV3TurboItem = NSMenuItem(title: "Distil-Whisper Large v3 Turbo (~600MB)", action: #selector(setEngine(_:)), keyEquivalent: "")
            distilV3TurboItem.target = self
            distilV3TurboItem.tag = 607
            menu.addItem(distilV3TurboItem)

            let largev3TurboItem = NSMenuItem(title: "Whisper Large v3 Turbo", action: #selector(setEngine(_:)), keyEquivalent: "")
            largev3TurboItem.target = self
            largev3TurboItem.tag = 609
            menu.addItem(largev3TurboItem)

            let largev3TurboCompItem = NSMenuItem(title: "Whisper Large v3 Turbo (632MB)", action: #selector(setEngine(_:)), keyEquivalent: "")
            largev3TurboCompItem.target = self
            largev3TurboCompItem.tag = 610
            menu.addItem(largev3TurboCompItem)

            let moonTinyItem = NSMenuItem(title: "Moonshine Tiny (bundled)", action: #selector(setEngine(_:)), keyEquivalent: "")
            moonTinyItem.target = self
            moonTinyItem.tag = 608
            menu.addItem(moonTinyItem)
        }

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

        // Pause media / mute sound while dictating
        let pauseHeader = NSMenuItem(title: "While Dictating:", action: nil, keyEquivalent: "")
        pauseHeader.isEnabled = false
        menu.addItem(pauseHeader)

        let pauseToggle = NSMenuItem(title: "Pause Media / Sound", action: #selector(togglePauseMedia), keyEquivalent: "")
        pauseToggle.target = self
        pauseToggle.tag = 900
        pauseToggle.state = MediaController.shared.enabled ? .on : .off
        menu.addItem(pauseToggle)

        let methodSubmenu = NSMenu()
        let pauseAppsItem = NSMenuItem(title: "Pause Media Players", action: #selector(setPauseMethod(_:)), keyEquivalent: "")
        pauseAppsItem.target = self
        pauseAppsItem.representedObject = "pauseApps" as NSString
        methodSubmenu.addItem(pauseAppsItem)
        let muteItem = NSMenuItem(title: "Mute All Sound", action: #selector(setPauseMethod(_:)), keyEquivalent: "")
        muteItem.target = self
        muteItem.representedObject = "muteSystem" as NSString
        methodSubmenu.addItem(muteItem)
        let methodItem = NSMenuItem(title: "Method", action: nil, keyEquivalent: "")
        methodItem.tag = 910
        methodItem.submenu = methodSubmenu
        menu.addItem(methodItem)

        let appsItem = NSMenuItem(title: "Apps to Pause", action: nil, keyEquivalent: "")
        appsItem.tag = 920
        appsItem.submenu = NSMenu()
        menu.addItem(appsItem)

        updatePauseMethodMenu()
        updatePauseAppsMenu()

        menu.addItem(NSMenuItem.separator())

        // Live captions across the screen with the active cursor
        let capHeader = NSMenuItem(title: "Live Captions:", action: nil, keyEquivalent: "")
        capHeader.isEnabled = false
        menu.addItem(capHeader)

        let capToggle = NSMenuItem(title: "Show Live Captions", action: #selector(toggleCaptions), keyEquivalent: "")
        capToggle.target = self
        capToggle.tag = 930
        capToggle.state = CaptionOverlayController.shared.enabled ? .on : .off
        menu.addItem(capToggle)

        let capSizeSub = NSMenu()
        for s in [8, 10, 12, 14, 18, 24, 32, 40, 52, 64] {
            let it = NSMenuItem(title: "\(s)px", action: #selector(setCaptionFontSize(_:)), keyEquivalent: "")
            it.target = self
            it.representedObject = s as NSNumber
            capSizeSub.addItem(it)
        }
        let capSizeItem = NSMenuItem(title: "Font Size", action: nil, keyEquivalent: "")
        capSizeItem.tag = 940
        capSizeItem.submenu = capSizeSub
        menu.addItem(capSizeItem)

        let capPosSub = NSMenu()
        let capTop = NSMenuItem(title: "Top", action: #selector(setCaptionPosition(_:)), keyEquivalent: "")
        capTop.target = self; capTop.representedObject = "top" as NSString
        capPosSub.addItem(capTop)
        let capBottom = NSMenuItem(title: "Bottom", action: #selector(setCaptionPosition(_:)), keyEquivalent: "")
        capBottom.target = self; capBottom.representedObject = "bottom" as NSString
        capPosSub.addItem(capBottom)
        let capPosItem = NSMenuItem(title: "Position", action: nil, keyEquivalent: "")
        capPosItem.tag = 950
        capPosItem.submenu = capPosSub
        menu.addItem(capPosItem)

        let capAlignSub = NSMenu()
        for (title, value) in [("Left", "left"), ("Center", "center"), ("Right", "right")] {
            let it = NSMenuItem(title: title, action: #selector(setCaptionAlignment(_:)), keyEquivalent: "")
            it.target = self
            it.representedObject = value as NSString
            capAlignSub.addItem(it)
        }
        let capAlignItem = NSMenuItem(title: "Alignment", action: nil, keyEquivalent: "")
        capAlignItem.tag = 960
        capAlignItem.submenu = capAlignSub
        menu.addItem(capAlignItem)

        let capBgItem = NSMenuItem(title: "Background", action: #selector(toggleCaptionBackground), keyEquivalent: "")
        capBgItem.target = self
        capBgItem.tag = 970
        capBgItem.state = CaptionOverlayController.shared.showBackground ? .on : .off
        menu.addItem(capBgItem)

        let capOpacitySub = NSMenu()
        for pct in [100, 85, 72, 55, 40, 25, 10] {
            let it = NSMenuItem(title: "\(pct)%", action: #selector(setCaptionOpacity(_:)), keyEquivalent: "")
            it.target = self
            it.representedObject = pct as NSNumber
            capOpacitySub.addItem(it)
        }
        let capOpacityItem = NSMenuItem(title: "Translucency", action: nil, keyEquivalent: "")
        capOpacityItem.tag = 980
        capOpacityItem.submenu = capOpacitySub
        menu.addItem(capOpacityItem)

        updateCaptionMenus()

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
        case 606:
            currentEngine = "distil-large-v3"
        case 607:
            currentEngine = "distil-large-v3-turbo"
        case 608:
            currentEngine = "moonshine-tiny"
        case 609:
            currentEngine = "whisper-large-v3-turbo"
        case 610:
            currentEngine = "whisper-large-v3-turbo-632"
        default:
            break
        }
        onEngineChanged?(currentEngine)
    }

    private var downloadFlashTimer: Timer?
    private var flashingTag: Int = 0
    private var flashState: Bool = false

    private func updateEngineMenu() {
        let engineMap: [(tag: Int, mode: String, whisperModel: WhisperManager.Model?)] = [
            (601, "apple", nil),
            (602, "whisper-tiny", .tiny),
            (603, "whisper-base", .base),
            (604, "whisper-small", .small),
            (605, "whisper-medium", .medium),
            (606, "distil-large-v3", .distilLargeV3),
            (607, "distil-large-v3-turbo", .distilLargeV3Turbo),
            (609, "whisper-large-v3-turbo", .largev3Turbo),
            (610, "whisper-large-v3-turbo-632", .largev3TurboCompressed),
            (608, "moonshine-tiny", nil),  // bundled
        ]
        for entry in engineMap {
            guard let item = menu.item(withTag: entry.tag) else { continue }
            item.state = currentEngine == entry.mode ? .on : .off

            // Gray out non-local whisper models (but keep them clickable)
            if let model = entry.whisperModel {
                let isLocal = speechManager.whisperManager.isModelLocal(model)
                if !isLocal && currentEngine != entry.mode {
                    let attrs: [NSAttributedString.Key: Any] = [
                        .foregroundColor: NSColor.secondaryLabelColor,
                        .font: NSFont.menuFont(ofSize: 0),
                    ]
                    item.attributedTitle = NSAttributedString(string: item.title, attributes: attrs)
                } else {
                    item.attributedTitle = nil  // reset to normal
                }
            }
        }
    }

    /// Start flashing a menu item (while model downloads)
    func startDownloadFlash(forEngine mode: String) {
        let tagMap: [String: Int] = [
            "whisper-tiny": 602, "whisper-base": 603, "whisper-small": 604,
            "whisper-medium": 605, "distil-large-v3": 606, "distil-large-v3-turbo": 607,
            "whisper-large-v3-turbo": 609, "whisper-large-v3-turbo-632": 610,
        ]
        guard let tag = tagMap[mode] else { return }
        flashingTag = tag
        flashState = false
        downloadFlashTimer?.invalidate()
        downloadFlashTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in
            guard let self = self, let item = self.menu.item(withTag: self.flashingTag) else { return }
            self.flashState.toggle()
            let color: NSColor = self.flashState ? .systemOrange : .secondaryLabelColor
            let attrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: color,
                .font: NSFont.menuFont(ofSize: 0),
            ]
            item.attributedTitle = NSAttributedString(string: item.title, attributes: attrs)
        }
    }

    /// Stop flashing
    func stopDownloadFlash() {
        downloadFlashTimer?.invalidate()
        downloadFlashTimer = nil
        flashingTag = 0
        updateEngineMenu()
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

    // MARK: - Pause Media / Mute While Dictating

    @objc private func togglePauseMedia() {
        MediaController.shared.enabled.toggle()
        if let item = menu.item(withTag: 900) {
            item.state = MediaController.shared.enabled ? .on : .off
        }
    }

    @objc private func setPauseMethod(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let method = MediaController.Method(rawValue: raw) else { return }
        MediaController.shared.method = method
        updatePauseMethodMenu()
        updatePauseAppsMenu()
    }

    private func updatePauseMethodMenu() {
        guard let methodItem = menu.item(withTag: 910), let sub = methodItem.submenu else { return }
        let current = MediaController.shared.method.rawValue
        for item in sub.items {
            if let raw = item.representedObject as? String {
                item.state = raw == current ? .on : .off
            }
        }
        methodItem.title = MediaController.shared.method == .muteSystem
            ? "Method: Mute All Sound" : "Method: Pause Players"
    }

    private func updatePauseAppsMenu() {
        guard let appsItem = menu.item(withTag: 920), let sub = appsItem.submenu else { return }
        sub.removeAllItems()

        let enabled = MediaController.shared.apps
        var all = MediaController.commonApps
        for app in enabled where !all.contains(app) { all.append(app) }

        for app in all {
            let item = NSMenuItem(title: app, action: #selector(togglePauseApp(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = app as NSString
            item.state = enabled.contains(app) ? .on : .off
            sub.addItem(item)
        }
        sub.addItem(NSMenuItem.separator())
        let addItem = NSMenuItem(title: "Add App…", action: #selector(addPauseApp), keyEquivalent: "")
        addItem.target = self
        sub.addItem(addItem)

        // Only relevant when pausing players (mute mode covers everything).
        appsItem.isEnabled = MediaController.shared.method == .pauseApps
    }

    @objc private func togglePauseApp(_ sender: NSMenuItem) {
        guard let app = sender.representedObject as? String else { return }
        var list = MediaController.shared.apps
        if list.contains(app) {
            list.removeAll { $0 == app }
        } else {
            list.append(app)
        }
        MediaController.shared.apps = list
        updatePauseAppsMenu()
    }

    @objc private func addPauseApp() {
        let panel = NSOpenPanel()
        panel.title = "Choose a media app to pause while dictating"
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let name = url.deletingPathExtension().lastPathComponent
        var list = MediaController.shared.apps
        if !list.contains(name) { list.append(name) }
        MediaController.shared.apps = list
        updatePauseAppsMenu()
    }

    // MARK: - Live Captions

    @objc private func toggleCaptions() {
        CaptionOverlayController.shared.enabled.toggle()
        if let item = menu.item(withTag: 930) {
            item.state = CaptionOverlayController.shared.enabled ? .on : .off
        }
    }

    @objc private func setCaptionFontSize(_ sender: NSMenuItem) {
        guard let size = sender.representedObject as? NSNumber else { return }
        CaptionOverlayController.shared.fontSize = CGFloat(size.intValue)
        updateCaptionMenus()
        CaptionOverlayController.shared.preview()
    }

    @objc private func setCaptionPosition(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String else { return }
        CaptionOverlayController.shared.position = value
        updateCaptionMenus()
        CaptionOverlayController.shared.preview()
    }

    @objc private func setCaptionAlignment(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String else { return }
        CaptionOverlayController.shared.alignment = value
        updateCaptionMenus()
        CaptionOverlayController.shared.preview()
    }

    @objc private func toggleCaptionBackground() {
        CaptionOverlayController.shared.showBackground.toggle()
        updateCaptionMenus()
        CaptionOverlayController.shared.preview()
    }

    @objc private func setCaptionOpacity(_ sender: NSMenuItem) {
        guard let pct = sender.representedObject as? NSNumber else { return }
        // Choosing a translucency level implies you want a background.
        CaptionOverlayController.shared.showBackground = true
        CaptionOverlayController.shared.backgroundOpacity = Double(pct.intValue) / 100.0
        updateCaptionMenus()
        CaptionOverlayController.shared.preview()
    }

    private func updateCaptionMenus() {
        let cap = CaptionOverlayController.shared
        if let sizeItem = menu.item(withTag: 940), let sub = sizeItem.submenu {
            for it in sub.items {
                if let s = it.representedObject as? NSNumber {
                    it.state = Int(cap.fontSize) == s.intValue ? .on : .off
                }
            }
            sizeItem.title = "Font Size: \(Int(cap.fontSize))px"
        }
        if let posItem = menu.item(withTag: 950), let sub = posItem.submenu {
            for it in sub.items {
                if let v = it.representedObject as? String { it.state = cap.position == v ? .on : .off }
            }
            posItem.title = "Position: \(cap.position.capitalized)"
        }
        if let alignItem = menu.item(withTag: 960), let sub = alignItem.submenu {
            for it in sub.items {
                if let v = it.representedObject as? String { it.state = cap.alignment == v ? .on : .off }
            }
            alignItem.title = "Alignment: \(cap.alignment.capitalized)"
        }
        if let bgItem = menu.item(withTag: 970) {
            bgItem.state = cap.showBackground ? .on : .off
        }
        if let opItem = menu.item(withTag: 980), let sub = opItem.submenu {
            let currentPct = Int((cap.backgroundOpacity * 100).rounded())
            for it in sub.items {
                if let p = it.representedObject as? NSNumber { it.state = p.intValue == currentPct ? .on : .off }
            }
            opItem.title = "Translucency: \(currentPct)%"
            opItem.isEnabled = cap.showBackground
        }
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
