import Cocoa
import ApplicationServices

/// Strategies for inserting transcribed text at the cursor.
///
/// Real dictation apps (Wispr Flow, superwhisper, OpenWhispr, FluidVoice) moved
/// OFF clipboard-paste: synthetic Cmd+V is dropped at random (Chrome/Electron)
/// and, crucially, collides with a physically-held trigger key (Control+Cmd+V
/// isn't paste; Fn+Delete is forward-delete). The reliable method is
/// `CGEventKeyboardSetUnicodeString` from a PRIVATE event source with explicitly
/// empty flags, so held modifiers can't reach the synthesized events.
enum TextInjector {
    enum Method: String, CaseIterable {
        case paste          // clipboard + Cmd+V, hidSystemState source (the legacy / current path)
        case pastePrivate   // clipboard + Cmd+V, private source + explicit flags
        case unicode        // CGEventKeyboardSetUnicodeString, private source, empty flags, posted to HID tap
        case unicodePid     // same, but posted directly to the target process (bypasses HID modifier merge)
    }

    static func insert(_ text: String, method: Method) {
        switch method {
        case .paste:        pasteViaClipboard(text, isolated: false)
        case .pastePrivate: pasteViaClipboard(text, isolated: true)
        case .unicode:      typeUnicode(text, pid: nil)
        case .unicodePid:   typeUnicode(text, pid: NSWorkspace.shared.frontmostApplication?.processIdentifier)
        }
    }

    // MARK: - Unicode typing (the robust method)

    /// Type `text` directly as Unicode key events. Private source + empty flags =
    /// immune to physically-held modifier keys. Chunked to ≤20 UTF-16 units (many
    /// apps read no more per event), never splitting a surrogate pair.
    static func typeUnicode(_ text: String, pid: pid_t?) {
        let src = CGEventSource(stateID: .privateState)
        let u = Array(text.utf16)
        var i = 0
        while i < u.count {
            var end = min(i + 20, u.count)
            if end < u.count && UTF16.isLeadSurrogate(u[end - 1]) { end -= 1 }
            postUnicode(Array(u[i..<end]), src: src, down: true, pid: pid)
            postUnicode(Array(u[i..<end]), src: src, down: false, pid: pid)
            i = end
            usleep(1500)
        }
    }

    private static func postUnicode(_ chunk: [UniChar], src: CGEventSource?, down: Bool, pid: pid_t?) {
        guard let e = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: down) else { return }
        e.flags = []   // critical: no modifiers, regardless of what's physically held
        e.setIntegerValueField(.eventSourceUserData, value: kSyntheticEventMarker)
        var mutable = chunk
        mutable.withUnsafeBufferPointer { buf in
            e.keyboardSetUnicodeString(stringLength: buf.count, unicodeString: buf.baseAddress)
        }
        if let pid = pid { e.postToPid(pid) } else { e.post(tap: .cghidEventTap) }
    }

    // MARK: - Clipboard paste (legacy)

    static func pasteViaClipboard(_ text: String, isolated: Bool) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        usleep(30000)
        let src = CGEventSource(stateID: isolated ? .privateState : .hidSystemState)
        func key(_ vk: CGKeyCode, _ down: Bool, _ flags: CGEventFlags) {
            guard let e = CGEvent(keyboardEventSource: src, virtualKey: vk, keyDown: down) else { return }
            e.flags = flags
            e.setIntegerValueField(.eventSourceUserData, value: kSyntheticEventMarker)
            e.post(tap: .cghidEventTap)
            usleep(8000)
        }
        key(55, true, .maskCommand)   // Cmd down
        key(9,  true, .maskCommand)   // V down
        key(9,  false, .maskCommand)  // V up
        key(55, false, [])            // Cmd up
    }

    // MARK: - Accessibility insert

    @discardableResult
    static func axInsert(_ text: String) -> Bool {
        let sys = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(sys, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
              let focused = focusedRef else { return false }
        let el = focused as! AXUIElement
        return AXUIElementSetAttributeValue(el, kAXSelectedTextAttribute as CFString, text as CFString) == .success
    }

    // MARK: - Delete (for incremental replace)

    /// Backspace `count` times. Private source + empty flags so a held Fn can't
    /// turn these into forward-delete.
    static func deleteBackward(_ count: Int) {
        guard count > 0 else { return }
        let src = CGEventSource(stateID: .privateState)
        for _ in 0..<count {
            postKey(51, src: src, down: true)
            postKey(51, src: src, down: false)
            usleep(1200)
        }
    }

    private static func postKey(_ vk: CGKeyCode, src: CGEventSource?, down: Bool) {
        guard let e = CGEvent(keyboardEventSource: src, virtualKey: vk, keyDown: down) else { return }
        e.flags = []
        e.setIntegerValueField(.eventSourceUserData, value: kSyntheticEventMarker)
        e.post(tap: .cghidEventTap)
    }

    // MARK: - Test helpers (synthetically hold a modifier to reproduce hold-to-talk)

    static func holdModifier(_ vk: CGKeyCode, _ flag: CGEventFlags) {
        let src = CGEventSource(stateID: .hidSystemState)
        guard let e = CGEvent(keyboardEventSource: src, virtualKey: vk, keyDown: true) else { return }
        e.flags = flag
        e.post(tap: .cghidEventTap)
    }

    static func releaseModifier(_ vk: CGKeyCode) {
        let src = CGEventSource(stateID: .hidSystemState)
        guard let e = CGEvent(keyboardEventSource: src, virtualKey: vk, keyDown: false) else { return }
        e.flags = []
        e.post(tap: .cghidEventTap)
    }
}
