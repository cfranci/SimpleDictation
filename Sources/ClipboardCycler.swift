import Cocoa

/// Intercepts Cmd+V system-wide to enable clipboard history cycling.
/// First Cmd+V pastes normally. While Cmd is still held, each subsequent V press
/// undoes the previous paste and replaces it with the next item from clipboard history.
/// Releasing Cmd or clicking anywhere resets the cycle.
class ClipboardCycler {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var cycleIndex: Int = -1
    private var isCycling = false
    private var suppressNextVUp = false
    private var lastPastedLength: Int = 0
    private let syntheticMarker: Int64 = 0x434C4950
    var enabled: Bool = false  // off by default until user enables

    var getClipboardHistory: (() -> [String])?
    var onCyclingStateChanged: ((Bool) -> Void)?

    func start() {
        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue) |
                                 (1 << CGEventType.keyUp.rawValue) |
                                 (1 << CGEventType.flagsChanged.rawValue) |
                                 (1 << CGEventType.leftMouseDown.rawValue) |
                                 (1 << CGEventType.rightMouseDown.rawValue)

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: clipboardCyclerCallback,
            userInfo: selfPtr
        ) else {
            slog("Failed to create event tap — check accessibility permissions")
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        slog("Event tap created successfully")
    }

    func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // Re-enable tap if system disabled it
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
                slog("Re-enabled event tap after system disable")
            }
            return Unmanaged.passUnretained(event)
        }

        // If cycling is disabled, pass everything through
        guard enabled else {
            return Unmanaged.passUnretained(event)
        }

        // Pass through our own synthetic events
        if event.getIntegerValueField(.eventSourceUserData) == syntheticMarker {
            return Unmanaged.passUnretained(event)
        }

        switch type {
        case .flagsChanged:
            if !event.flags.contains(.maskCommand) && cycleIndex >= 0 {
                slog("Cmd released, resetting cycle")
                resetCycle()
            }
            return Unmanaged.passUnretained(event)

        case .leftMouseDown, .rightMouseDown:
            if cycleIndex >= 0 {
                slog("Click detected, resetting cycle")
                resetCycle()
            }
            return Unmanaged.passUnretained(event)

        case .keyDown:
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            let flags = event.flags

            // Cmd+V only (no Shift/Ctrl/Alt)
            if keyCode == 9 && flags.contains(.maskCommand) &&
               !flags.contains(.maskShift) && !flags.contains(.maskControl) && !flags.contains(.maskAlternate) {

                guard let history = getClipboardHistory?(), !history.isEmpty else {
                    slog("Cmd+V but no clipboard history, passing through")
                    return Unmanaged.passUnretained(event)
                }

                if cycleIndex == -1 {
                    // First Cmd+V: pass through normally, start tracking
                    cycleIndex = 0
                    lastPastedLength = history[0].count
                    onCyclingStateChanged?(true)
                    slog("First Cmd+V, tracking cycle (history has \(history.count) items, len=\(lastPastedLength))")
                    return Unmanaged.passUnretained(event)
                } else if !isCycling {
                    // Subsequent V: cycle to next history item
                    cycleIndex = (cycleIndex + 1) % history.count
                    suppressNextVUp = true
                    slog("Cycling to index \(cycleIndex): \(String(history[cycleIndex].prefix(30)))")
                    performCycle(to: cycleIndex, history: history)
                    return nil // suppress this V keyDown
                } else {
                    slog("Suppressing V (cycle in progress)")
                    return nil // suppress while async cycle in progress
                }
            }

            // Any other key resets
            if cycleIndex >= 0 {
                slog("Other key pressed, resetting cycle")
                resetCycle()
            }
            return Unmanaged.passUnretained(event)

        case .keyUp:
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            if keyCode == 9 && suppressNextVUp {
                suppressNextVUp = false
                return nil // suppress matching V keyUp
            }
            return Unmanaged.passUnretained(event)

        default:
            return Unmanaged.passUnretained(event)
        }
    }

    private func performCycle(to index: Int, history: [String]) {
        guard index < history.count else { return }
        isCycling = true
        let prevLen = lastPastedLength
        let newText = history[index]

        // Try Accessibility API first (works in all apps reliably).
        // Falls back to keyboard events if AX fails.
        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            guard let self = self else { return }

            if self.axReplacePastedText(prevLen: prevLen, newText: newText) {
                self.slog("Cycle to index \(index) via AX (replaced \(prevLen) chars with \(newText.count))")
            } else {
                self.slog("AX failed, falling back to keyboard for index \(index)")
                self.keyboardReplacePastedText(prevLen: prevLen, newText: newText)
            }

            // Update clipboard to match what we just pasted
            DispatchQueue.main.sync {
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(newText, forType: .string)
            }

            self.lastPastedLength = newText.count
            self.isCycling = false
        }
    }

    /// Use Accessibility API to select and replace the last pasted text.
    /// Returns true if it worked.
    private func axReplacePastedText(prevLen: Int, newText: String) -> Bool {
        guard prevLen > 0 else { return false }

        // Get the focused UI element
        let systemWide = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        let focusErr = AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedRef)
        guard focusErr == .success, let focused = focusedRef else {
            slog("AX: no focused element (err=\(focusErr.rawValue))")
            return false
        }
        let element = focused as! AXUIElement

        // Get current value
        var valueRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef) == .success,
              let currentValue = valueRef as? String else {
            slog("AX: can't read value")
            return false
        }

        // Get current insertion point (selected text range)
        var rangeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success else {
            slog("AX: can't read selection range")
            return false
        }
        var range = CFRange(location: 0, length: 0)
        AXValueGetValue(rangeRef as! AXValue, .cfRange, &range)

        // The cursor should be right after the last paste.
        // Select backwards by prevLen chars.
        let cursorPos = range.location
        let selectStart = max(0, cursorPos - prevLen)
        let selectLen = cursorPos - selectStart

        // Set selected text range to cover the previously pasted text
        var selectRange = CFRange(location: selectStart, length: selectLen)
        guard let axRange = AXValueCreate(.cfRange, &selectRange) else {
            slog("AX: can't create range")
            return false
        }
        let setRangeErr = AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, axRange)
        guard setRangeErr == .success else {
            slog("AX: can't set selection (err=\(setRangeErr.rawValue))")
            return false
        }

        // Replace the selected text with the new text
        let setTextErr = AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, newText as CFString)
        guard setTextErr == .success else {
            slog("AX: can't set selected text (err=\(setTextErr.rawValue))")
            return false
        }

        slog("AX: replaced chars \(selectStart)..\(cursorPos) with \(newText.count) chars")
        return true
    }

    /// Keyboard fallback: Cmd+Z undo then Cmd+V paste.
    private func keyboardReplacePastedText(prevLen: Int, newText: String) {
        let src = CGEventSource(stateID: .privateState)

        // Cmd+Z to undo
        postKey(src: src, keyCode: 6, down: true, flags: [.maskCommand])
        postKey(src: src, keyCode: 6, down: false, flags: [.maskCommand])
        usleep(100000)

        // Set clipboard
        DispatchQueue.main.sync {
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(newText, forType: .string)
        }
        usleep(50000)

        // Cmd+V to paste
        postKey(src: src, keyCode: 9, down: true, flags: [.maskCommand])
        postKey(src: src, keyCode: 9, down: false, flags: [.maskCommand])
        usleep(50000)
    }

    private func postKey(src: CGEventSource?, keyCode: CGKeyCode, down: Bool, flags: CGEventFlags = []) {
        guard let event = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: down) else { return }
        if !flags.isEmpty {
            event.flags = flags
        }
        event.setIntegerValueField(.eventSourceUserData, value: syntheticMarker)
        event.post(tap: .cghidEventTap)
    }

    private func resetCycle() {
        cycleIndex = -1
        suppressNextVUp = false
        isCycling = false
        lastPastedLength = 0
        onCyclingStateChanged?(false)
    }

    private func slog(_ msg: String) {
        NSLog("[ClipboardCycler] %@", msg)
        let line = "\(Date()): [ClipboardCycler] \(msg)\n"
        let path = "/tmp/simpledictation.log"
        if let handle = FileHandle(forWritingAtPath: path) {
            handle.seekToEndOfFile()
            handle.write(line.data(using: .utf8)!)
            handle.closeFile()
        } else {
            FileManager.default.createFile(atPath: path, contents: line.data(using: .utf8))
        }
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
    }

    deinit {
        stop()
    }
}

private func clipboardCyclerCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, userInfo: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let userInfo = userInfo else {
        return Unmanaged.passUnretained(event)
    }
    let cycler = Unmanaged<ClipboardCycler>.fromOpaque(userInfo).takeUnretainedValue()
    return cycler.handleEvent(proxy: proxy, type: type, event: event)
}
