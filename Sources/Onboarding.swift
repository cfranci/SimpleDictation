import SwiftUI
import AVFoundation
import Speech
import ApplicationServices

// MARK: - Permission state

enum PermState {
    case granted, denied, notDetermined

    var label: String {
        switch self {
        case .granted:       return "Granted"
        case .denied:        return "Denied — open System Settings"
        case .notDetermined: return "Not granted yet"
        }
    }
    var color: Color {
        switch self {
        case .granted:       return .green
        case .denied:        return .red
        case .notDetermined: return .secondary
        }
    }
    var symbol: String {
        switch self {
        case .granted:       return "checkmark.circle.fill"
        case .denied:        return "xmark.circle.fill"
        case .notDetermined: return "circle.dashed"
        }
    }
}

/// Live view of the three system permissions the app needs. Accessibility has no
/// callback, so we poll; mic/speech update immediately after their request sheets.
final class PermissionsModel: ObservableObject {
    @Published var accessibility: PermState = .notDetermined
    @Published var microphone: PermState = .notDetermined
    @Published var speech: PermState = .notDetermined

    private var timer: Timer?

    func refresh() {
        accessibility = AXIsProcessTrusted() ? .granted : .notDetermined

        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:          microphone = .granted
        case .denied, .restricted: microphone = .denied
        default:                   microphone = .notDetermined
        }

        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:          speech = .granted
        case .denied, .restricted: speech = .denied
        default:                   speech = .notDetermined
        }
    }

    func startPolling() {
        refresh()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    func stopPolling() {
        timer?.invalidate()
        timer = nil
    }

    var allEssentialGranted: Bool {
        accessibility == .granted && microphone == .granted
    }

    // MARK: Requests

    func requestAccessibility() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
        openAccessibilitySettings()
    }

    func requestMicrophone() {
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] _ in
            DispatchQueue.main.async { self?.refresh() }
        }
    }

    func requestSpeech() {
        SFSpeechRecognizer.requestAuthorization { [weak self] _ in
            DispatchQueue.main.async { self?.refresh() }
        }
    }

    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Onboarding window

struct OnboardingView: View {
    @ObservedObject var store: DictationSettingsStore
    @ObservedObject var perms: PermissionsModel
    var onFinish: () -> Void

    @State private var step = 0
    @State private var showLargeModels = false
    private let titles = ["Welcome", "Permissions", "Preferences", "You're ready"]
    private var lastStep: Int { titles.count - 1 }

    var body: some View {
        VStack(spacing: 0) {
            StepHeader(index: step, titles: titles)
            Divider()

            ScrollView {
                Group {
                    switch step {
                    case 0: welcome
                    case 1: permissions
                    case 2: preferences
                    default: ready
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(26)
            }

            Divider()
            footer
        }
        .frame(width: 560, height: 600)
        .onAppear { perms.startPolling() }
        .onDisappear { perms.stopPolling() }
    }

    // MARK: Pages

    private var welcome: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 8)
            DotPreview(store: store).frame(width: 84, height: 84)
            Text("Welcome to SimpleDictation")
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)
            Text("Hold a key, speak, and your words are typed right where your cursor is.")
                .font(.title3)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Chip(icon: "lock.fill", text: "100% on-device — your voice never leaves your Mac", tint: .green)

            VStack(alignment: .leading, spacing: 10) {
                SetupStepRow(number: 1, text: "Grant a couple of quick permissions")
                SetupStepRow(number: 2, text: "Pick your engine and trigger key")
                SetupStepRow(number: 3, text: "Hold, speak, release — you're dictating")
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.04)))
            Spacer(minLength: 8)
        }
    }

    private var permissions: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Grant permissions")
                .font(.title.bold())
            Text("SimpleDictation only works locally. Here's exactly what each one is for:")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            PermissionRow(
                symbol: "accessibility", title: "Accessibility", tag: "Required", tint: .blue,
                why: "Types the transcribed text into your app, reads selected text, and listens for your trigger key system-wide.",
                state: perms.accessibility,
                numberedHint: ["Click \u{201C}Open Settings\u{201D} below", "Find SimpleDictation in the list", "Flip its switch on — this screen updates itself"],
                action: { perms.requestAccessibility() }, actionLabel: "Open Settings")

            PermissionRow(
                symbol: "mic.fill", title: "Microphone", tag: "Required", tint: .pink,
                why: "Captures your speech while you hold the trigger key. Transcribed on-device, never uploaded.",
                state: perms.microphone, numberedHint: nil,
                action: { perms.requestMicrophone() }, actionLabel: "Grant")

            PermissionRow(
                symbol: "waveform", title: "Speech Recognition", tag: "Optional", tint: .purple,
                why: "Only used by the built-in Apple engine. The Whisper, Moonshine and Whistle engines don't need it.",
                state: perms.speech, numberedHint: nil,
                action: { perms.requestSpeech() }, actionLabel: "Grant")

            if perms.allEssentialGranted {
                Banner(icon: "checkmark.seal.fill", tint: .green,
                       text: "All set — you're good to continue.")
            } else {
                Banner(icon: "info.circle.fill", tint: .secondary,
                       text: "Accessibility and Microphone are needed to dictate. You can continue now and finish them anytime from the menu.")
            }
        }
    }

    private var preferences: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Pick your preferences")
                .font(.title.bold())
            Text("You can change all of these later in Settings.")
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                Text("Dictation engine").font(.callout.weight(.semibold))
                EngineChooser(store: store, showLarge: $showLargeModels)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Trigger key").font(.callout.weight(.semibold))
                Picker("Mode", selection: $store.triggerMode) {
                    Text("Hold to talk").tag("hold")
                    Text("Hands-free").tag("toggle")
                }.pickerStyle(.segmented)
                Text(store.triggerMode == "toggle"
                     ? "Triple-tap to start listening, single tap to stop, double-tap for Return."
                     : "Hold a key to talk, release to type. Double-tap for Return.")
                    .font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                KeycapKeyboard(store: store)
                Toggle("I'm using a non-Mac (PC) keyboard", isOn: $store.pcKeyboard)
                    .font(.callout)
                if store.pcKeyboard {
                    Label("On a PC keyboard the ⊞ Win key acts as ⌘ and Alt acts as ⌥. Fn usually can't be used — Control or Alt work best.",
                          systemImage: "info.circle")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Tap a key to toggle it. Highlighted keys are active. Double-tap a trigger while dictating to press Return.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Toggle("Show live captions while dictating", isOn: $store.captionsEnabled)
            Spacer(minLength: 0)
        }
    }

    private var ready: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 4)
            Image(systemName: perms.allEssentialGranted ? "checkmark.seal.fill" : "hand.wave.fill")
                .font(.system(size: 52))
                .foregroundStyle(perms.allEssentialGranted ? .green : .blue)
            Text(perms.allEssentialGranted ? "You're ready" : "Almost there")
                .font(.largeTitle.bold())

            VStack(alignment: .leading, spacing: 12) {
                Text("How to dictate").font(.headline)
                if store.triggerMode == "toggle" {
                    SetupStepRow(number: 1, text: "Triple-tap \(triggerKeysText) to start listening")
                    SetupStepRow(number: 2, text: "Speak naturally — hands-free")
                    SetupStepRow(number: 3, text: "Single tap to stop — your words are typed at the cursor")
                } else {
                    SetupStepRow(number: 1, text: "Hold \(triggerKeysText)")
                    SetupStepRow(number: 2, text: "Speak naturally")
                    SetupStepRow(number: 3, text: "Release — your words are typed at the cursor")
                }
                Divider()
                Label("Double-tap the key to press Return.", systemImage: "return")
                    .font(.caption).foregroundStyle(.secondary)
                Label("Right-click the floating mic any time for Settings.", systemImage: "cursorarrow.rays")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.04)))

            VStack(alignment: .leading, spacing: 10) {
                Text("More you can do").font(.headline)
                FeatureToggle(icon: "doc.on.clipboard.fill", tint: .teal,
                              title: "Clipboard cycling",
                              desc: "Hold ⌘ and tap V repeatedly to paste older clipboard items.",
                              isOn: $store.clipboardCycling)
                FeatureToggle(icon: "speaker.slash.fill", tint: .orange,
                              title: "Pause media while dictating",
                              desc: "Auto-pause music / mute sound when you start, restore after.",
                              isOn: $store.pauseMediaEnabled)
                FeatureInfo(icon: "captions.bubble.fill", tint: .blue,
                            title: "Live captions",
                            desc: "See your words on screen as you speak.")
                FeatureInfo(icon: "cpu.fill", tint: .purple,
                            title: "Swap engines anytime",
                            desc: "Apple, Whistle, Whisper, Moonshine — switch in Settings.")
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.04)))

            if !perms.allEssentialGranted {
                Banner(icon: "exclamationmark.triangle.fill", tint: .orange,
                       text: "Accessibility and Microphone aren't both granted yet — dictation won't work until they are. Reopen setup from the menu's \u{201C}Setup Assistant\u{2026}\u{201D} anytime.")
            }
            Spacer(minLength: 4)
        }
    }

    private var triggerKeysText: String {
        var keys: [String] = []
        if store.modFn { keys.append("Fn") }
        if store.modControl { keys.append("Control") }
        if store.modOption { keys.append("Option") }
        if store.modCommand { keys.append("Command") }
        if keys.isEmpty { keys = ["Fn"] }
        return keys.joined(separator: " or ")
    }

    // MARK: Footer nav

    private var footer: some View {
        HStack {
            if step > 0 {
                Button("Back") { withAnimation { step -= 1 } }
            } else {
                Button("Skip setup") { onFinish() }
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if step < lastStep {
                Button(primaryLabel) { withAnimation { step += 1 } }
                    .keyboardShortcut(.defaultAction)
                    .controlSize(.large)
            } else {
                Button("Start dictating") { onFinish() }
                    .keyboardShortcut(.defaultAction)
                    .controlSize(.large)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var primaryLabel: String {
        switch step {
        case 0: return "Get Started"
        case 1: return perms.allEssentialGranted ? "Continue" : "Continue anyway"
        default: return "Continue"
        }
    }
}

// MARK: - Small building blocks

private struct StepHeader: View {
    let index: Int
    let titles: [String]
    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                ForEach(titles.indices, id: \.self) { i in
                    Capsule()
                        .fill(i <= index ? Color.accentColor : Color.secondary.opacity(0.22))
                        .frame(height: 4)
                }
            }
            HStack {
                Text("Step \(index + 1) of \(titles.count)")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(titles[index])
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 10)
    }
}

private struct SetupStepRow: View {
    let number: Int
    let text: String
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle().fill(Color.accentColor.opacity(0.15)).frame(width: 22, height: 22)
                Text("\(number)").font(.caption.bold()).foregroundStyle(Color.accentColor)
            }
            Text(text).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}

private struct Chip: View {
    let icon: String; let text: String; let tint: Color
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon).foregroundStyle(tint)
            Text(text).font(.caption)
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(Capsule().fill(tint.opacity(0.12)))
    }
}

private struct Banner: View {
    let icon: String; let tint: Color; let text: String
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon).foregroundStyle(tint)
            Text(text).font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(tint.opacity(0.10)))
    }
}

private struct PermissionRow: View {
    let symbol: String
    let title: String
    let tag: String
    let tint: Color
    let why: String
    let state: PermState
    let numberedHint: [String]?
    let action: () -> Void
    let actionLabel: String

    private var granted: Bool { state == .granted }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 22))
                    .foregroundStyle(granted ? .green : tint)
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(title).font(.headline)
                        TagPill(text: tag, required: tag == "Required")
                        Spacer(minLength: 0)
                        Image(systemName: state.symbol).foregroundStyle(state.color)
                        Text(state.label).font(.caption).foregroundStyle(state.color)
                    }
                    Text(why).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !granted {
                    Button(actionLabel, action: action)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }
            }
            if !granted, let hint = numberedHint {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(hint.indices, id: \.self) { i in
                        Text("\(i + 1).  \(hint[i])")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .padding(.leading, 42)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8)
            .fill(granted ? Color.green.opacity(0.08) : Color.primary.opacity(0.04)))
    }
}

private struct TagPill: View {
    let text: String; let required: Bool
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 9, weight: .bold))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill((required ? Color.orange : Color.secondary).opacity(0.18)))
            .foregroundStyle(required ? Color.orange : Color.secondary)
    }
}

// MARK: - Engine chooser (recommended + hidden big models)

struct EngineChooser: View {
    @ObservedObject var store: DictationSettingsStore
    @Binding var showLarge: Bool

    var body: some View {
        VStack(spacing: 6) {
            ForEach(EngineCatalog.everyday, id: \.id) { row($0) }

            Button {
                withAnimation { showLarge.toggle() }
            } label: {
                HStack {
                    Image(systemName: showLarge ? "chevron.down" : "chevron.right")
                    Text(showLarge ? "Hide large models" : "Show large models (big downloads)")
                    Spacer()
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)

            if showLarge {
                ForEach(EngineCatalog.largeModels, id: \.id) { row($0) }
            }
        }
    }

    private func row(_ engine: EngineCatalog.Engine) -> some View {
        let selected = store.engine == engine.id
        return Button {
            store.engine = engine.id
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(selected ? Color.accentColor : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(engine.title).font(.callout.weight(.medium))
                        if engine.recommended { EngineBadge(text: "Recommended", tint: .green) }
                        if engine.large { EngineBadge(text: "Large", tint: .orange) }
                    }
                    if selected {
                        Text(engine.blurb).font(.caption2).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8)
                .fill(selected ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.03)))
            .overlay(RoundedRectangle(cornerRadius: 8)
                .stroke(selected ? Color.accentColor.opacity(0.5) : Color.clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

struct EngineBadge: View {
    let text: String; let tint: Color
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 8, weight: .bold))
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(Capsule().fill(tint.opacity(0.18)))
            .foregroundStyle(tint)
    }
}

// MARK: - Visual trigger-key keyboard

struct KeycapKeyboard: View {
    @ObservedObject var store: DictationSettingsStore
    var body: some View {
        HStack(spacing: 10) {
            Keycap(symbol: "🌐", name: "Fn", active: store.modFn,
                   dimmed: store.pcKeyboard) { store.modFn.toggle() }
            Keycap(symbol: "⌃", name: store.pcKeyboard ? "Ctrl" : "Control", active: store.modControl) { store.modControl.toggle() }
            Keycap(symbol: "⌥", name: store.pcKeyboard ? "Alt" : "Option", active: store.modOption) { store.modOption.toggle() }
            Keycap(symbol: store.pcKeyboard ? "⊞" : "⌘", name: store.pcKeyboard ? "Win" : "Command", active: store.modCommand) { store.modCommand.toggle() }
        }
    }
}

private struct Keycap: View {
    let symbol: String
    let name: String
    let active: Bool
    var dimmed: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Text(symbol).font(.title3)
                Text(name).font(.system(size: 10, weight: .medium))
            }
            .frame(width: 74, height: 54)
            .background(RoundedRectangle(cornerRadius: 9)
                .fill(active ? Color.accentColor : Color.secondary.opacity(0.12)))
            .overlay(RoundedRectangle(cornerRadius: 9)
                .stroke(Color.primary.opacity(active ? 0 : 0.12), lineWidth: 1))
            .foregroundStyle(active ? Color.white : .primary)
            .opacity(dimmed ? 0.5 : 1)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Feature cards (last page)

private struct FeatureToggle: View {
    let icon: String; let tint: Color; let title: String; let desc: String
    @Binding var isOn: Bool
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).foregroundStyle(tint).frame(width: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.callout.weight(.medium))
                Text(desc).font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Toggle("", isOn: $isOn).labelsHidden()
        }
    }
}

private struct FeatureInfo: View {
    let icon: String; let tint: Color; let title: String; let desc: String
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).foregroundStyle(tint).frame(width: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.callout.weight(.medium))
                Text(desc).font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
}

/// Owns the single onboarding window instance.
final class OnboardingWindowController {
    static let shared = OnboardingWindowController()
    private var window: NSWindow?
    private let perms = PermissionsModel()

    static let completedKey = "hasCompletedOnboarding"

    func showIfFirstRun() {
        guard !UserDefaults.standard.bool(forKey: Self.completedKey) else { return }
        show()
    }

    func show() {
        if window == nil {
            let view = OnboardingView(store: .shared, perms: perms, onFinish: { [weak self] in
                UserDefaults.standard.set(true, forKey: Self.completedKey)
                self?.window?.close()
                self?.window = nil
            })
            let host = NSHostingController(rootView: view)
            let win = NSWindow(contentViewController: host)
            win.title = "Welcome to SimpleDictation"
            win.styleMask = [.titled, .closable]
            win.isReleasedWhenClosed = false
            window = win
        }
        if let win = window { placeWindowOnActiveScreen(win, fallbackSize: NSSize(width: 560, height: 600)) }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
