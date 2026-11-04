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
        case .authorized:        microphone = .granted
        case .denied, .restricted: microphone = .denied
        default:                 microphone = .notDetermined
        }

        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:        speech = .granted
        case .denied, .restricted: speech = .denied
        default:                 speech = .notDetermined
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
        // Prompts the system "allow in Accessibility" dialog, then surfaces the pane
        // so the user can flip the switch (the grant can't be made programmatically).
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
    private let lastStep = 3

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch step {
                case 0: welcome
                case 1: permissions
                case 2: preferences
                default: done
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(28)

            Divider()
            footer
        }
        .frame(width: 540, height: 560)
        .onAppear { perms.startPolling() }
        .onDisappear { perms.stopPolling() }
    }

    // MARK: Pages

    private var welcome: some View {
        VStack(spacing: 16) {
            Spacer()
            DotPreview(store: store).frame(width: 72, height: 72)
            Text("Welcome to SimpleDictation")
                .font(.largeTitle.bold())
            Text("Hold a key, speak, and your words are typed wherever your cursor is. Everything runs on-device — your voice never leaves your Mac.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 20)
            Spacer()
            Text("Let's grant a few permissions and pick your preferences.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    private var permissions: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Permissions")
                .font(.title2.bold())
            Text("SimpleDictation only works locally. Here's exactly what each permission is for:")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            PermissionRow(
                symbol: "accessibility", title: "Accessibility", tint: .blue,
                why: "Lets the app type the transcribed text into the app you're using, read the text you select, and listen for your trigger key system-wide.",
                state: perms.accessibility, action: { perms.requestAccessibility() },
                actionLabel: "Open Settings")

            PermissionRow(
                symbol: "mic.fill", title: "Microphone", tint: .pink,
                why: "Captures your speech while you hold the trigger key. Audio is transcribed on-device and never uploaded.",
                state: perms.microphone, action: { perms.requestMicrophone() },
                actionLabel: "Grant")

            PermissionRow(
                symbol: "waveform", title: "Speech Recognition", tint: .purple,
                why: "Used by the built-in Apple engine to convert speech to text on-device. (The Whisper, Moonshine and Whistle engines don't need this.)",
                state: perms.speech, action: { perms.requestSpeech() },
                actionLabel: "Grant")

            Spacer()
            Text("Accessibility must be switched on manually in System Settings — the app can't flip it for you. It updates here automatically once you do.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var preferences: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Preferences")
                .font(.title2.bold())
            Text("You can change all of these later in Settings.")
                .font(.callout).foregroundStyle(.secondary)

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Picker("Dictation engine", selection: $store.engine) {
                        ForEach(EngineCatalog.available, id: \.id) { Text($0.title).tag($0.id) }
                    }
                    Text(EngineCatalog.blurb(for: store.engine))
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }.padding(6)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Trigger key — hold to dictate").font(.callout)
                    HStack {
                        Toggle("Fn 🌐", isOn: $store.modFn)
                        Toggle("Control", isOn: $store.modControl)
                        Toggle("Option", isOn: $store.modOption)
                        Toggle("Command", isOn: $store.modCommand)
                    }.toggleStyle(.checkbox)
                }.padding(6)
            }

            Toggle("Show live captions while dictating", isOn: $store.captionsEnabled)

            Spacer()
        }
    }

    private var done: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: perms.allEssentialGranted ? "checkmark.seal.fill" : "hand.wave.fill")
                .font(.system(size: 54))
                .foregroundStyle(perms.allEssentialGranted ? .green : .blue)
            Text("You're all set")
                .font(.largeTitle.bold())
            Text("Hold your trigger key, speak, and release. A floating mic also lives on your screen — right-click it any time for Settings.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 20)
            if !perms.allEssentialGranted {
                Text("Heads up: Accessibility and Microphone aren't both granted yet — dictation won't work until they are.")
                    .font(.caption).foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
    }

    // MARK: Footer nav

    private var footer: some View {
        HStack {
            if step > 0 {
                Button("Back") { step -= 1 }
            }
            Spacer()
            PageDots(count: lastStep + 1, index: step)
            Spacer()
            if step < lastStep {
                Button(step == 0 ? "Get Started" : "Continue") { step += 1 }
                    .keyboardShortcut(.defaultAction)
            } else {
                Button("Finish") { onFinish() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }
}

private struct PermissionRow: View {
    let symbol: String
    let title: String
    let tint: Color
    let why: String
    let state: PermState
    let action: () -> Void
    let actionLabel: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 22))
                .foregroundStyle(tint)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(title).font(.headline)
                    Image(systemName: state.symbol).foregroundStyle(state.color)
                    Text(state.label).font(.caption).foregroundStyle(state.color)
                }
                Text(why).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if state != .granted {
                Button(actionLabel, action: action)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))
    }
}

private struct PageDots: View {
    let count: Int
    let index: Int
    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { i in
                Circle()
                    .fill(i == index ? Color.accentColor : Color.secondary.opacity(0.35))
                    .frame(width: 7, height: 7)
            }
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
            win.center()
            window = win
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
