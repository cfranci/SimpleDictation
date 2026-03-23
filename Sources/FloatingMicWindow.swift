import Cocoa

/// A small floating pill window that serves as the primary dictation UI.
/// Always visible on screen regardless of menu bar/notch issues.
class FloatingMicWindow: NSPanel {
    private var micView: MicPillView!
    private weak var speechManager: SpeechManager?
    private var onToggleRecording: (() -> Void)?
    private var onEnterPressed: (() -> Void)?
    private var onRightClick: ((NSView) -> Void)?
    private var audioLevelTimer: Timer?
    private var lastClickTime: Date = Date.distantPast
    private var isDragging = false
    private var dragStartPoint: NSPoint = .zero
    private var windowStartOrigin: NSPoint = .zero

    private static let posXKey = "floatingMicX"
    private static let posYKey = "floatingMicY"

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init(speechManager: SpeechManager, onToggleRecording: @escaping () -> Void, onEnterPressed: @escaping () -> Void, onRightClick: @escaping (NSView) -> Void) {
        self.speechManager = speechManager
        self.onToggleRecording = onToggleRecording
        self.onEnterPressed = onEnterPressed
        self.onRightClick = onRightClick

        let pillWidth: CGFloat = 44
        let pillHeight: CGFloat = 58

        // Restore saved position or default to top-right
        let screen = NSScreen.main ?? NSScreen.screens.first!
        let defaults = UserDefaults.standard
        let x: CGFloat
        let y: CGFloat
        if defaults.object(forKey: FloatingMicWindow.posXKey) != nil {
            x = CGFloat(defaults.double(forKey: FloatingMicWindow.posXKey))
            y = CGFloat(defaults.double(forKey: FloatingMicWindow.posYKey))
        } else {
            x = screen.frame.maxX - pillWidth - 12
            y = screen.frame.maxY - pillHeight - 40
        }

        super.init(
            contentRect: NSRect(x: x, y: y, width: pillWidth, height: pillHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        self.level = .floating
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        self.isMovableByWindowBackground = false // We handle dragging manually
        self.hidesOnDeactivate = false
        self.becomesKeyOnlyIfNeeded = true
        self.acceptsMouseMovedEvents = true
        self.ignoresMouseEvents = false

        micView = MicPillView(frame: NSRect(x: 0, y: 0, width: pillWidth, height: pillHeight))
        micView.onLeftClick = { [weak self] in
            self?.handleLeftClick()
        }
        micView.onRightClick = { [weak self] in
            guard let self = self, let view = self.micView else { return }
            self.onRightClick?(view)
        }
        micView.onDragStart = { [weak self] event in
            guard let self = self else { return }
            self.isDragging = true
            self.dragStartPoint = NSEvent.mouseLocation
            self.windowStartOrigin = self.frame.origin
        }
        micView.onDragMove = { [weak self] event in
            guard let self = self, self.isDragging else { return }
            let current = NSEvent.mouseLocation
            let dx = current.x - self.dragStartPoint.x
            let dy = current.y - self.dragStartPoint.y
            self.setFrameOrigin(NSPoint(x: self.windowStartOrigin.x + dx, y: self.windowStartOrigin.y + dy))
        }
        micView.onDragEnd = { [weak self] in
            guard let self = self else { return }
            self.isDragging = false
            // Persist position
            let origin = self.frame.origin
            UserDefaults.standard.set(Double(origin.x), forKey: FloatingMicWindow.posXKey)
            UserDefaults.standard.set(Double(origin.y), forKey: FloatingMicWindow.posYKey)
        }
        self.contentView = micView

        // Set initial engine label
        updateEngineLabel(speechManager.engineMode)
        updateAppearance(recording: false)
        self.orderFrontRegardless()
    }

    func handleLeftClick() {
        let now = Date()
        if now.timeIntervalSince(lastClickTime) < 0.4 {
            lastClickTime = Date.distantPast
            onEnterPressed?()
        } else {
            lastClickTime = now
            onToggleRecording?()
        }
    }

    func updateAppearance(recording: Bool) {
        micView.isRecording = recording
        micView.needsDisplay = true

        if recording {
            startAudioLevelTimer()
        } else {
            stopAudioLevelTimer()
            micView.audioLevel = 0
            micView.needsDisplay = true
        }
    }

    func updateEngineLabel(_ engineMode: String) {
        let label: String
        switch engineMode {
        case "apple": label = "SR"
        case "whisper-tiny": label = "W-T"
        case "whisper-base": label = "W-B"
        case "whisper-small": label = "W-S"
        case "whisper-medium": label = "W-M"
        case "distil-large-v3": label = "DL3"
        case "distil-large-v3-turbo": label = "DL3T"
        case "moonshine-tiny": label = "MS"
        default: label = engineMode
        }
        micView.engineLabel = label
        micView.needsDisplay = true
    }

    private func startAudioLevelTimer() {
        stopAudioLevelTimer()
        audioLevelTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self = self, let sm = self.speechManager, let view = self.micView, view.isRecording else { return }
            view.audioLevel = CGFloat(sm.audioLevel)
            view.needsDisplay = true
        }
    }

    private func stopAudioLevelTimer() {
        audioLevelTimer?.invalidate()
        audioLevelTimer = nil
    }

    deinit {
        stopAudioLevelTimer()
    }
}

/// The visual content of the floating mic button
class MicPillView: NSView {
    var isRecording = false
    var audioLevel: CGFloat = 0
    var engineLabel: String = "SR"
    var onLeftClick: (() -> Void)?
    var onRightClick: (() -> Void)?
    var onDragStart: ((NSEvent) -> Void)?
    var onDragMove: ((NSEvent) -> Void)?
    var onDragEnd: (() -> Void)?

    private var mouseDownPoint: NSPoint = .zero
    private var didDrag = false

    override var acceptsFirstResponder: Bool { true }

    // Accept clicks without requiring window activation first
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        mouseDownPoint = event.locationInWindow
        didDrag = false
        onDragStart?(event)
    }

    override func mouseDragged(with event: NSEvent) {
        let current = event.locationInWindow
        let dx = abs(current.x - mouseDownPoint.x)
        let dy = abs(current.y - mouseDownPoint.y)
        if dx > 3 || dy > 3 {
            didDrag = true
        }
        onDragMove?(event)
    }

    override func mouseUp(with event: NSEvent) {
        onDragEnd?()
        if !didDrag {
            onLeftClick?()
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        onRightClick?()
    }

    override func draw(_ dirtyRect: NSRect) {
        // Circle area: top 44x44 of the 44x58 view
        let circleRect = NSRect(x: 0, y: bounds.height - 44, width: 44, height: 44).insetBy(dx: 2, dy: 2)
        let path = NSBezierPath(ovalIn: circleRect)

        if isRecording {
            // Base red color with audio level affecting brightness
            let level = min(max(audioLevel, 0), 1.0)
            let alpha: CGFloat = 0.6 + 0.4 * level
            NSColor(red: 0.9, green: 0.1, blue: 0.1, alpha: alpha).setFill()
        } else {
            NSColor(white: 0.15, alpha: 0.85).setFill()
        }
        path.fill()

        // Audio level ring when recording
        if isRecording && audioLevel > 0.01 {
            let ringWidth: CGFloat = 1.5 + 2.5 * min(max(audioLevel, 0), 1.0)
            let ringRect = circleRect.insetBy(dx: -ringWidth / 2, dy: -ringWidth / 2)
            let ringPath = NSBezierPath(ovalIn: ringRect)
            ringPath.lineWidth = ringWidth
            NSColor(red: 1.0, green: 0.3, blue: 0.3, alpha: 0.5 + 0.5 * min(max(audioLevel, 0), 1.0)).setStroke()
            ringPath.stroke()
        }

        // Mic icon
        let cx = circleRect.midX
        let cy = circleRect.midY

        if isRecording {
            NSColor.white.setFill()
            NSColor.white.setStroke()
        } else {
            NSColor(white: 0.75, alpha: 1.0).setFill()
            NSColor(white: 0.75, alpha: 1.0).setStroke()
        }

        // Mic body
        let micW: CGFloat = 8
        let micH: CGFloat = 14
        let micRect = NSRect(x: cx - micW / 2, y: cy - 1, width: micW, height: micH)
        let micPath = NSBezierPath(roundedRect: micRect, xRadius: micW / 2, yRadius: micW / 2)
        micPath.fill()

        // Mic arc
        let arcPath = NSBezierPath()
        arcPath.lineWidth = 1.5
        let arcRadius: CGFloat = 7
        let arcCenterY = cy + 3
        arcPath.appendArc(withCenter: NSPoint(x: cx, y: arcCenterY),
                          radius: arcRadius,
                          startAngle: 200, endAngle: 340)
        arcPath.stroke()

        // Stand
        let standPath = NSBezierPath()
        standPath.lineWidth = 1.5
        standPath.move(to: NSPoint(x: cx, y: arcCenterY - arcRadius))
        standPath.line(to: NSPoint(x: cx, y: cy - 10))
        standPath.stroke()

        // Base
        let basePath = NSBezierPath()
        basePath.lineWidth = 1.5
        basePath.move(to: NSPoint(x: cx - 5, y: cy - 10))
        basePath.line(to: NSPoint(x: cx + 5, y: cy - 10))
        basePath.stroke()

        // Engine label below the circle
        let labelRect = NSRect(x: 0, y: 0, width: bounds.width, height: 14)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 9, weight: .medium),
            .foregroundColor: NSColor(white: 0.85, alpha: 1.0),
            .paragraphStyle: paragraphStyle,
        ]
        (engineLabel as NSString).draw(in: labelRect, withAttributes: attrs)
    }
}
