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
    private var spinnerTimer: Timer?
    private var lastClickTime: Date = Date.distantPast
    private var circleSize: CGFloat
    private var isDragging = false
    private var dragStartPoint: NSPoint = .zero
    private var windowStartOrigin: NSPoint = .zero

    private static let posXKey = "floatingMicX"
    private static let posYKey = "floatingMicY"

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init(speechManager: SpeechManager, circleSize: CGFloat = 40, onToggleRecording: @escaping () -> Void, onEnterPressed: @escaping () -> Void, onRightClick: @escaping (NSView) -> Void) {
        self.speechManager = speechManager
        self.onToggleRecording = onToggleRecording
        self.onEnterPressed = onEnterPressed
        self.onRightClick = onRightClick
        self.circleSize = circleSize

        let pillWidth = circleSize + 12
        let pillHeight = circleSize + 26

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

    func updateSize(_ newSize: CGFloat) {
        circleSize = newSize
        let newWidth = newSize + 12
        let newHeight = newSize + 26
        let oldCenter = NSPoint(x: frame.midX, y: frame.midY)
        let newFrame = NSRect(
            x: oldCenter.x - newWidth / 2,
            y: oldCenter.y - newHeight / 2,
            width: newWidth,
            height: newHeight
        )
        setFrame(newFrame, display: false)
        micView.frame = NSRect(x: 0, y: 0, width: newWidth, height: newHeight)
        micView.updateTrackingAreas()
        micView.needsDisplay = true
        UserDefaults.standard.set(Double(newFrame.origin.x), forKey: FloatingMicWindow.posXKey)
        UserDefaults.standard.set(Double(newFrame.origin.y), forKey: FloatingMicWindow.posYKey)
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

    func updateProcessing(_ processing: Bool) {
        if processing {
            micView.isProcessing = true
            micView.spinnerAngle = 0
            micView.spinnerPhase = 0
            startSpinnerTimer()
        } else {
            // Signal finish: let it complete the current orbit back to 0 degrees
            micView.isProcessing = false
        }
        micView.needsDisplay = true
    }

    func updateDownloading(_ downloading: Bool) {
        if downloading {
            micView.isDownloading = true
            micView.spinnerAngle = 0
            micView.spinnerPhase = 0
            startSpinnerTimer()
        } else {
            micView.isDownloading = false
        }
        micView.needsDisplay = true
    }

    private func startSpinnerTimer() {
        guard spinnerTimer == nil else { return }
        spinnerTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            guard let self = self, let view = self.micView else { return }
            let spinning = view.isProcessing || view.isDownloading || view.spinnerPhase > 0

            guard spinning else {
                self.stopSpinnerTimer()
                view.spinnerAngle = 0
                view.spinnerPhase = 0
                view.needsDisplay = true
                return
            }

            let speed: CGFloat = 4.0

            if view.spinnerPhase < 1.0 {
                // Phase 0..1: expanding out from center
                view.spinnerPhase = min(view.spinnerPhase + 0.06, 1.0)
                view.spinnerAngle += speed * view.spinnerPhase
            } else if view.isProcessing || view.isDownloading {
                // Phase 1: normal orbiting
                view.spinnerAngle += speed
            } else {
                // Finishing: complete the orbit back to ~0 degrees then stop
                view.spinnerAngle += speed
                // Once we cross 360 (back near start), begin shrinking
                if view.spinnerAngle >= 360.0 {
                    view.spinnerPhase += 0.06
                }
                if view.spinnerPhase >= 2.0 {
                    view.spinnerAngle = 0
                    view.spinnerPhase = 0
                    self.stopSpinnerTimer()
                }
            }

            if view.spinnerAngle >= 360.0 && (view.isProcessing || view.isDownloading) {
                view.spinnerAngle -= 360.0
            }

            view.needsDisplay = true
        }
    }

    private func stopSpinnerTimer() {
        spinnerTimer?.invalidate()
        spinnerTimer = nil
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
        case "whisper-large-v3-turbo": label = "LT"
        case "whisper-large-v3-turbo-632": label = "LT6"
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
        stopSpinnerTimer()
    }
}

/// The visual content of the floating mic button
class MicPillView: NSView {
    var isRecording = false
    var isProcessing = false
    var isDownloading = false
    var spinnerAngle: CGFloat = 0
    /// 0 = not spinning, 0..1 = expanding out from main dot, 1 = orbiting, 1..2 = finishing orbit back to start
    var spinnerPhase: CGFloat = 0
    var audioLevel: CGFloat = 0
    var engineLabel: String = "SR"
    var isHovering = false
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

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        needsDisplay = true
    }

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
        let padding: CGFloat = 6
        let labelHeight: CGFloat = 14
        let circleSize = bounds.width - padding * 2
        let circleRect = NSRect(x: padding, y: labelHeight + padding, width: circleSize, height: circleSize)
        let path = NSBezierPath(ovalIn: circleRect)

        if isRecording {
            NSColor(red: 1.0, green: 0.15, blue: 0.15, alpha: 1.0).setFill()
        } else if isProcessing {
            NSColor(white: 0.15, alpha: 0.35).setFill()
        } else {
            let bgAlpha: CGFloat = isHovering ? 0.45 : 0.25
            NSColor(white: 0.15, alpha: bgAlpha).setFill()
        }
        path.fill()

        if isRecording {
            let level = min(max(audioLevel, 0), 1.0)
            let ringWidth: CGFloat = 2.0 + 3.0 * level
            let ringRect = circleRect.insetBy(dx: -ringWidth, dy: -ringWidth)
            let ringPath = NSBezierPath(ovalIn: ringRect)
            ringPath.lineWidth = ringWidth
            NSColor(red: 1.0, green: 0.2, blue: 0.2, alpha: 0.4 + 0.6 * level).setStroke()
            ringPath.stroke()
        }

        // Spinner: small dot orbiting the circle (red = processing, blue = downloading)
        if spinnerPhase > 0 {
            let dotColor: NSColor = isDownloading
                ? NSColor(red: 0.2, green: 0.5, blue: 1.0, alpha: 1.0)
                : NSColor(red: 1.0, green: 0.2, blue: 0.2, alpha: 1.0)

            let maxDotRadius: CGFloat = max(2.0, 2.5 * (circleSize / 40.0))
            let orbitRadius = circleSize / 2.0 + 3.0

            // Scale dot size based on phase (grow in at start, shrink out at end)
            let sizeFactor: CGFloat
            if spinnerPhase < 1.0 {
                sizeFactor = spinnerPhase  // expanding
            } else if spinnerPhase > 1.0 {
                sizeFactor = max(0, 2.0 - spinnerPhase)  // shrinking back
            } else {
                sizeFactor = 1.0
            }

            // Lerp orbit radius: dot starts at center of main circle, expands to orbit
            let currentOrbit = orbitRadius * sizeFactor
            let dotRadius = maxDotRadius * sizeFactor

            let angleRad = spinnerAngle * .pi / 180.0
            let dotX = circleRect.midX + currentOrbit * cos(angleRad)
            let dotY = circleRect.midY + currentOrbit * sin(angleRad)
            let dotRect = NSRect(x: dotX - dotRadius, y: dotY - dotRadius, width: dotRadius * 2, height: dotRadius * 2)
            dotColor.setFill()
            NSBezierPath(ovalIn: dotRect).fill()

            // Fading trail (only when fully orbiting)
            if sizeFactor > 0.8 {
                let trailAlphaBase = min(1.0, (sizeFactor - 0.8) / 0.2)
                for i in 1...4 {
                    let trailAngle = (spinnerAngle - CGFloat(i) * 6.0) * .pi / 180.0
                    let tx = circleRect.midX + currentOrbit * cos(trailAngle)
                    let ty = circleRect.midY + currentOrbit * sin(trailAngle)
                    let trailR = dotRadius * (1.0 - CGFloat(i) * 0.15)
                    let trailRect = NSRect(x: tx - trailR, y: ty - trailR, width: trailR * 2, height: trailR * 2)
                    let alpha = trailAlphaBase * (0.5 - CGFloat(i) * 0.1)
                    dotColor.withAlphaComponent(alpha).setFill()
                    NSBezierPath(ovalIn: trailRect).fill()
                }
            }
        }

        let cx = circleRect.midX
        let cy = circleRect.midY
        let scale = circleSize / 40.0

        if isRecording {
            NSColor.white.setFill()
            NSColor.white.setStroke()
        } else {
            let iconAlpha: CGFloat = isHovering ? 0.6 : 0.25
            NSColor(white: 0.75, alpha: iconAlpha).setFill()
            NSColor(white: 0.75, alpha: iconAlpha).setStroke()
        }

        let lw = max(1.0, 1.5 * scale)
        let micW: CGFloat = 8 * scale
        let micH: CGFloat = 14 * scale
        let micRect = NSRect(x: cx - micW / 2, y: cy - 1 * scale, width: micW, height: micH)
        let micPath = NSBezierPath(roundedRect: micRect, xRadius: micW / 2, yRadius: micW / 2)
        micPath.fill()

        let arcPath = NSBezierPath()
        arcPath.lineWidth = lw
        let arcRadius: CGFloat = 7 * scale
        let arcCenterY = cy + 3 * scale
        arcPath.appendArc(withCenter: NSPoint(x: cx, y: arcCenterY),
                          radius: arcRadius,
                          startAngle: 200, endAngle: 340)
        arcPath.stroke()

        let standPath = NSBezierPath()
        standPath.lineWidth = lw
        standPath.move(to: NSPoint(x: cx, y: arcCenterY - arcRadius))
        standPath.line(to: NSPoint(x: cx, y: cy - 10 * scale))
        standPath.stroke()

        let basePath = NSBezierPath()
        basePath.lineWidth = lw
        basePath.move(to: NSPoint(x: cx - 5 * scale, y: cy - 10 * scale))
        basePath.line(to: NSPoint(x: cx + 5 * scale, y: cy - 10 * scale))
        basePath.stroke()

        if isHovering && !isRecording {
            let labelRect = NSRect(x: 0, y: 0, width: bounds.width, height: labelHeight)
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = .center
            let fontSize = max(7, 9 * scale)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: fontSize, weight: .medium),
                .foregroundColor: NSColor(white: 0.85, alpha: 0.6),
                .paragraphStyle: paragraphStyle,
            ]
            (engineLabel as NSString).draw(in: labelRect, withAttributes: attrs)
        }
    }
}
