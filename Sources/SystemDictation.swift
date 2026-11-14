import AppKit
import SwiftUI

/// macOS has its own Dictation with a "press a key twice" shortcut (fn, Control
/// or Command). When it is on, double-tapping a trigger key to start hands-free
/// listening would start Apple's dictation as well.
enum SystemDictation {
    /// True when macOS Dictation is switched on and its keyboard shortcut is not
    /// set to Off. We can't tell which key it uses, so any double-tap may clash.
    static var shortcutMayConflict: Bool {
        let assistant = CFPreferencesCopyAppValue("Dictation Enabled" as CFString,
                                                  "com.apple.assistant.support" as CFString) as? Bool ?? false
        let hiToolbox = (CFPreferencesCopyAppValue("AppleDictationAutoEnable" as CFString,
                                                   "com.apple.HIToolbox" as CFString) as? Int) == 1
        guard assistant || hiToolbox else { return false }
        // Symbolic hotkey 164 is the Dictation shortcut; "Off" stores enabled = 0.
        if let keys = CFPreferencesCopyAppValue("AppleSymbolicHotKeys" as CFString,
                                                "com.apple.symbolichotkeys" as CFString) as? [String: Any],
           let entry = keys["164"] as? [String: Any],
           let enabled = entry["enabled"] as? Bool {
            return enabled
        }
        return true
    }

    static func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension?Dictation") {
            NSWorkspace.shared.open(url)
        }
    }
}

/// Shown next to the Hands-free option while the macOS shortcut is in the way.
/// Rechecks whenever the app comes back to the front, so it clears itself once
/// the user has changed the setting.
struct DictationConflictNotice: View {
    @State private var conflict = SystemDictation.shortcutMayConflict

    var body: some View {
        Group {
            if conflict {
                VStack(alignment: .leading, spacing: 8) {
                    Label("macOS Dictation also starts on a double-tap", systemImage: "exclamationmark.triangle.fill")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.orange)
                    Text("Both would start at once. In Keyboard settings, under Dictation, set Shortcut to Off or turn Dictation off.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Open Keyboard settings") { SystemDictation.openSettings() }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            conflict = SystemDictation.shortcutMayConflict
        }
    }
}
