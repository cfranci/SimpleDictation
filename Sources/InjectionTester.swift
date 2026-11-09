import Cocoa

/// Self-contained test harness for the text-injection methods. Opens a window
/// with a real NSTextView, then for every (method × held-modifier) combination:
/// clears the field, synthetically holds a modifier (reproducing hold-to-talk —
/// the case I couldn't test before), injects a known phrase, reads back what
/// actually landed, and writes PASS/FAIL to /tmp/inject-test-results.txt.
///
/// Trigger with: printf injecttest > ~/Library/Application Support/SimpleDictation/trigger
final class InjectionTester {
    static let shared = InjectionTester()
    private var window: NSWindow?
    private var textView: NSTextView?

    private let phrase = "the quick brown fox"
    private let resultsPath = "/tmp/inject-test-results.txt"

    func run() {
        let frame = NSRect(x: 0, y: 0, width: 520, height: 320)
        let scroll = NSScrollView(frame: frame)
        let tv = NSTextView(frame: frame)
        tv.font = NSFont.systemFont(ofSize: 15)
        tv.isRichText = false
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        scroll.documentView = tv
        scroll.hasVerticalScroller = true

        let win = NSWindow(contentRect: frame,
                           styleMask: [.titled, .closable],
                           backing: .buffered, defer: false)
        win.title = "SimpleDictation — Injection Test"
        win.contentView = scroll
        win.isReleasedWhenClosed = false
        placeWindowOnActiveScreen(win, fallbackSize: frame.size)
        self.window = win
        self.textView = tv

        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)
        win.makeFirstResponder(tv)

        // Let the window settle into focus, then run the matrix off-main so the
        // main run loop stays free to deliver the synthetic events to the field.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            DispatchQueue.global(qos: .userInitiated).async { self.runMatrix() }
        }
    }

    private struct Cond { let name: String; let vk: CGKeyCode?; let flag: CGEventFlags }

    private func runMatrix() {
        // NOTE: no "command" condition — a held Cmd turns the 'q' in "quick" into
        // Cmd+Q and quits the app. Control + Option are the realistic hold-to-talk
        // cases anyway and don't fire destructive shortcuts.
        let conds: [Cond] = [
            Cond(name: "none",    vk: nil, flag: []),
            Cond(name: "control", vk: 59,  flag: .maskControl),
            Cond(name: "option",  vk: 58,  flag: .maskAlternate),
        ]

        // Write header, then append each result immediately so a mid-run quit
        // still leaves partial data.
        write("INJECTION TEST  (expected: '\(phrase)')\n\n", append: false)

        for method in TextInjector.Method.allCases {
            for c in conds {
                clearField()
                usleep(120000)
                if let vk = c.vk { TextInjector.holdModifier(vk, c.flag) }
                usleep(40000)

                TextInjector.insert(phrase, method: method)
                usleep(350000)   // let events deliver to the field

                let got = readField()
                if let vk = c.vk { TextInjector.releaseModifier(vk) }
                usleep(60000)

                let pass = got == phrase
                let shown = got.replacingOccurrences(of: "\n", with: "\\n")
                write("\(pass ? "PASS" : "FAIL")  [\(pad(method.rawValue, 13)) \(pad(c.name, 8))]  got: '\(shown)'\n", append: true)
            }
            write("\n", append: true)
        }

        NSLog("[SimpleDictation] Injection test complete → %@", resultsPath)
        DispatchQueue.main.async {
            self.textView?.string = "Injection test complete.\nResults: \(self.resultsPath)"
        }
    }

    private func pad(_ s: String, _ n: Int) -> String {
        s.count >= n ? s : s + String(repeating: " ", count: n - s.count)
    }

    private func write(_ s: String, append: Bool) {
        if append, let fh = FileHandle(forWritingAtPath: resultsPath) {
            fh.seekToEndOfFile(); fh.write(s.data(using: .utf8)!); fh.closeFile()
        } else {
            try? s.write(toFile: resultsPath, atomically: true, encoding: .utf8)
        }
    }

    private func clearField() {
        DispatchQueue.main.sync {
            self.textView?.string = ""
            if let tv = self.textView { self.window?.makeFirstResponder(tv) }
        }
    }

    private func readField() -> String {
        DispatchQueue.main.sync { self.textView?.string ?? "" }
    }
}
