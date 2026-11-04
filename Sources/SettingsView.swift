import SwiftUI
import CoreAudio

// MARK: - Engine catalog

/// Static description of every dictation engine, so the picker and onboarding can
/// share one source of truth. Mirrors the tags/ids in StatusBarController.setEngine.
enum EngineCatalog {
    struct Engine { let id: String; let title: String; let blurb: String; let needs14: Bool; let recommended: Bool; let large: Bool }

    static let all: [Engine] = [
        .init(id: "apple",   title: "Apple Speech",
              blurb: "Built-in system dictation. Fast and always available; needs Speech Recognition permission.", needs14: false, recommended: true, large: false),
        .init(id: "whistle", title: "Whistle — 17 MB, on-device",
              blurb: "Tiny bundled model. CPU-only, no download, works on any Mac. Great low-footprint default.", needs14: false, recommended: true, large: false),
        .init(id: "whisper-tiny",   title: "Whisper Tiny (~40 MB)",
              blurb: "Smallest Whisper. Fast, lower accuracy. Downloads on first use.", needs14: true, recommended: false, large: false),
        .init(id: "whisper-base",   title: "Whisper Base (~140 MB)",
              blurb: "Small Whisper with a nice speed/accuracy balance.", needs14: true, recommended: true, large: false),
        .init(id: "whisper-small",  title: "Whisper Small (~460 MB)",
              blurb: "More accurate Whisper, a bit slower.", needs14: true, recommended: false, large: false),
        .init(id: "whisper-medium", title: "Whisper Medium (~1.5 GB)",
              blurb: "High-accuracy Whisper. Large download, heavier to run.", needs14: true, recommended: false, large: true),
        .init(id: "distil-large-v3", title: "Distil-Whisper Large v3 (~594 MB)",
              blurb: "Distilled large model — near-large accuracy, much faster.", needs14: true, recommended: false, large: true),
        .init(id: "distil-large-v3-turbo", title: "Distil-Whisper Large v3 Turbo (~600 MB)",
              blurb: "Turbo distilled large — fastest of the large-class Whispers.", needs14: true, recommended: false, large: true),
        .init(id: "whisper-large-v3-turbo", title: "Whisper Large v3 Turbo (~1.5 GB)",
              blurb: "Full large-v3 turbo. Top Whisper accuracy. Large download.", needs14: true, recommended: false, large: true),
        .init(id: "whisper-large-v3-turbo-632", title: "Whisper Large v3 Turbo (632 MB)",
              blurb: "Compressed large-v3 turbo — large accuracy, smaller footprint.", needs14: true, recommended: false, large: true),
        .init(id: "moonshine-tiny", title: "Moonshine Tiny (bundled)",
              blurb: "Bundled on-device model tuned for low latency on short phrases.", needs14: true, recommended: false, large: false),
    ]

    static var available: [Engine] {
        if #available(macOS 14, *) { return all }
        return all.filter { !$0.needs14 }
    }
    /// Everyday models shown by default (small/bundled). The big downloads are
    /// hidden until the user opts to see them.
    static var everyday: [Engine] { available.filter { !$0.large } }
    static var largeModels: [Engine] { available.filter { $0.large } }
    static func blurb(for id: String) -> String { all.first { $0.id == id }?.blurb ?? "" }
    static func title(for id: String) -> String { all.first { $0.id == id }?.title ?? id }
    static func isLarge(_ id: String) -> Bool { all.first { $0.id == id }?.large ?? false }
    static func isRecommended(_ id: String) -> Bool { all.first { $0.id == id }?.recommended ?? false }
}

// MARK: - Settings store

/// Bridges the app's UserDefaults + live controllers to SwiftUI. Each property
/// writes through to the real controller so changes apply immediately. The
/// `suppress` flag lets `configure(...)` seed values without re-triggering effects.
final class DictationSettingsStore: ObservableObject {
    static let shared = DictationSettingsStore()
    private let cap = CaptionOverlayController.shared

    weak var speechManager: SpeechManager?
    weak var statusBar: StatusBarController?
    private var suppress = false

    // Recognition
    @Published var engine: String          { didSet { guard !suppress else { return }; applyEngine() } }
    @Published var locale: String          { didSet { guard !suppress else { return }; speechManager?.setLocale(locale); UserDefaults.standard.set(locale, forKey: "dictationLocale") } }
    @Published var micID: AudioDeviceID     { didSet { guard !suppress else { return }; speechManager?.selectMic(micID) } }
    @Published var keepOnlyModel: Bool     { didSet { guard !suppress else { return }; applyKeepOnly() } }
    @Published var incrementalMode: Bool   { didSet { guard !suppress else { return }; speechManager?.incrementalMode = incrementalMode; UserDefaults.standard.set(incrementalMode, forKey: "incrementalMode") } }
    @Published var appEnabled: Bool        { didSet { guard !suppress else { return }; statusBar?.isEnabled = appEnabled; statusBar?.onEnabledChanged?(appEnabled) } }

    // Shortcuts (trigger modifiers)
    @Published var modFn: Bool      { didSet { applyModifiers() } }
    @Published var modControl: Bool { didSet { applyModifiers() } }
    @Published var modOption: Bool  { didSet { applyModifiers() } }
    @Published var modCommand: Bool { didSet { applyModifiers() } }
    /// Display-only: relabel modifier keys for a non-Mac (PC) keyboard
    /// (Option→Alt, Command→Win). The macOS-level modifier flags are identical.
    @Published var pcKeyboard: Bool { didSet { UserDefaults.standard.set(pcKeyboard, forKey: "pcKeyboardLayout") } }

    // Recording indicator
    @Published var dotStyle: DotStyle { didSet { DotSettings.style = dotStyle } }
    @Published var dotSpeed: DotSpeed { didSet { DotSettings.speed = dotSpeed } }
    @Published var customHue: Double  { didSet { DotSettings.customHue = CGFloat(customHue) } }
    @Published var dotOpacity: Double { didSet { DotSettings.opacity = CGFloat(dotOpacity) } }
    @Published var motionWave: Bool    { didSet { setMotion(.wave, motionWave) } }
    @Published var motionSpin: Bool    { didSet { setMotion(.spin, motionSpin) } }
    @Published var motionRipple: Bool  { didSet { setMotion(.ripple, motionRipple) } }
    @Published var motionBreathe: Bool { didSet { setMotion(.breathe, motionBreathe) } }
    @Published var iconSize: Double    { didSet { guard !suppress else { return }; UserDefaults.standard.set(Int(iconSize), forKey: "floatingMicSize"); statusBar?.onSizeChanged?(CGFloat(iconSize)) } }
    @Published var showMicSymbol: Bool { didSet { DotSettings.showMicSymbol = showMicSymbol } }

    // Captions
    @Published var captionsEnabled: Bool    { didSet { cap.enabled = captionsEnabled } }
    @Published var position: String         { didSet { cap.position = position; cap.preview() } }
    @Published var alignment: String        { didSet { cap.alignment = alignment; cap.preview() } }
    @Published var fontSize: Double         { didSet { cap.fontSize = CGFloat(fontSize); cap.preview() } }
    @Published var textColor: Color         { didSet { cap.textColor = NSColor(textColor); cap.preview() } }
    @Published var textOpacity: Double      { didSet { cap.textOpacity = textOpacity; cap.preview() } }
    @Published var showBackground: Bool     { didSet { cap.showBackground = showBackground; cap.preview() } }
    @Published var backgroundOpacity: Double { didSet { cap.backgroundOpacity = backgroundOpacity; cap.preview() } }
    @Published var showWindowShadow: Bool   { didSet { cap.showWindowShadow = showWindowShadow; cap.preview() } }

    // Behavior
    @Published var clipboardCycling: Bool  { didSet { guard !suppress else { return }; UserDefaults.standard.set(clipboardCycling, forKey: "clipboardCyclingEnabled"); statusBar?.onClipboardCyclingChanged?(clipboardCycling) } }
    @Published var pauseMediaEnabled: Bool { didSet { guard !suppress else { return }; MediaController.shared.enabled = pauseMediaEnabled } }
    @Published var pauseMethod: String     { didSet { guard !suppress else { return }; MediaController.shared.method = MediaController.Method(rawValue: pauseMethod) ?? .pauseApps } }
    @Published var pausedApps: Set<String> { didSet { guard !suppress else { return }; MediaController.shared.apps = Array(pausedApps).sorted() } }

    var mics: [SpeechManager.AudioDeviceInfo] { speechManager?.availableMics ?? [] }

    private func setMotion(_ m: DotMotion, _ on: Bool) {
        var s = DotSettings.motions
        if on { s.insert(m) } else { s.remove(m) }
        DotSettings.motions = s
    }

    private func applyEngine() {
        statusBar?.currentEngine = engine        // refresh engine-menu checkmarks
        statusBar?.onEngineChanged?(engine)       // persist + preload + relabel
        if keepOnlyModel, #available(macOS 14, *) { speechManager?.pruneModelsKeepingCurrent() }
        if statusBar == nil { UserDefaults.standard.set(engine, forKey: "dictationEngine") }
    }

    private func applyKeepOnly() {
        UserDefaults.standard.set(keepOnlyModel, forKey: "keepOnlySelectedModel")
        if keepOnlyModel, #available(macOS 14, *) { speechManager?.pruneModelsKeepingCurrent() }
    }

    private func applyModifiers() {
        guard !suppress else { return }
        var set = Set<String>()
        if modFn { set.insert("fn") }
        if modControl { set.insert("control") }
        if modOption { set.insert("option") }
        if modCommand { set.insert("command") }
        if set.isEmpty {           // never allow zero modifiers — re-arm Fn
            suppress = true; modFn = true; suppress = false
            set = ["fn"]
        }
        statusBar?.enabledModifiers = set
        statusBar?.onModifiersChanged?(set)
    }

    /// Called from AppDelegate once the live controllers exist: wire references and
    /// seed the values that only they know (mic, enabled, locale, incremental).
    func configure(speechManager: SpeechManager, statusBar: StatusBarController) {
        self.speechManager = speechManager
        self.statusBar = statusBar
        suppress = true
        speechManager.refreshMicList()
        micID = speechManager.selectedMicID
        appEnabled = statusBar.isEnabled
        locale = speechManager.currentLocale
        incrementalMode = speechManager.incrementalMode
        suppress = false
    }

    init() {
        let d = UserDefaults.standard
        engine = d.string(forKey: "dictationEngine") ?? "apple"
        locale = d.string(forKey: "dictationLocale") ?? "en-US"
        micID = 0
        keepOnlyModel = d.bool(forKey: "keepOnlySelectedModel")
        incrementalMode = d.bool(forKey: "incrementalMode")
        appEnabled = true

        let mods = Set((d.array(forKey: "enabledModifiers") as? [String]) ?? ["fn", "option"])
        modFn = mods.contains("fn")
        modControl = mods.contains("control")
        modOption = mods.contains("option")
        modCommand = mods.contains("command")
        pcKeyboard = d.bool(forKey: "pcKeyboardLayout")

        dotStyle = DotSettings.style
        dotSpeed = DotSettings.speed
        customHue = Double(DotSettings.customHue)
        dotOpacity = Double(DotSettings.opacity)
        let motions = DotSettings.motions
        motionWave = motions.contains(.wave)
        motionSpin = motions.contains(.spin)
        motionRipple = motions.contains(.ripple)
        motionBreathe = motions.contains(.breathe)
        iconSize = Double(d.object(forKey: "floatingMicSize") as? Int ?? 40)
        showMicSymbol = DotSettings.showMicSymbol

        captionsEnabled = cap.enabled
        position = cap.position
        alignment = cap.alignment
        fontSize = Double(cap.fontSize)
        textColor = Color(cap.textColor)
        textOpacity = cap.textOpacity
        showBackground = cap.showBackground
        backgroundOpacity = cap.backgroundOpacity
        showWindowShadow = cap.showWindowShadow

        clipboardCycling = d.bool(forKey: "clipboardCyclingEnabled")
        pauseMediaEnabled = MediaController.shared.enabled
        pauseMethod = MediaController.shared.method.rawValue
        pausedApps = Set(MediaController.shared.apps)
    }
}

/// A small live-animated preview of the recording dot with the current style.
struct DotPreview: View {
    @ObservedObject var store: DictationSettingsStore
    var body: some View {
        TimelineView(.animation) { timeline in
            let phase = timeline.date.timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: .pi * 2) * Double(store.dotSpeed.multiplier)
            let motions = currentMotions()
            if let img = DotEffect.image(style: store.dotStyle, motions: motions,
                                         phase: CGFloat(phase), customHue: CGFloat(store.customHue),
                                         size: 44, opacity: CGFloat(store.dotOpacity)) {
                Image(nsImage: img).resizable().aspectRatio(contentMode: .fit)
            } else {
                Circle().fill(.red)
            }
        }
    }
    private func currentMotions() -> Set<DotMotion> {
        var s: Set<DotMotion> = []
        if store.motionWave { s.insert(.wave) }
        if store.motionSpin { s.insert(.spin) }
        if store.motionRipple { s.insert(.ripple) }
        if store.motionBreathe { s.insert(.breathe) }
        return s
    }
}

// MARK: - Tabbed settings

struct SettingsView: View {
    @ObservedObject var store: DictationSettingsStore

    var body: some View {
        TabView {
            RecognitionTab(store: store)
                .tabItem { Label("Recognition", systemImage: "waveform") }
            ShortcutsTab(store: store)
                .tabItem { Label("Shortcuts", systemImage: "command") }
            IndicatorTab(store: store)
                .tabItem { Label("Indicator", systemImage: "circle.hexagongrid.fill") }
            CaptionsTab(store: store)
                .tabItem { Label("Captions", systemImage: "captions.bubble") }
            BehaviorTab(store: store)
                .tabItem { Label("Behavior", systemImage: "slider.horizontal.3") }
        }
        .frame(width: 520, height: 600)
        .onAppear { store.speechManager?.refreshMicList() }
    }
}

private struct RecognitionTab: View {
    @ObservedObject var store: DictationSettingsStore
    var body: some View {
        Form {
            Section {
                Toggle("Dictation enabled", isOn: $store.appEnabled)
            }
            Section("Engine") {
                Picker("Engine", selection: $store.engine) {
                    ForEach(EngineCatalog.available, id: \.id) { Text($0.title).tag($0.id) }
                }
                Text(EngineCatalog.blurb(for: store.engine))
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if #available(macOS 14, *) {
                    Toggle("Keep only the selected model (reclaim disk from others)", isOn: $store.keepOnlyModel)
                }
                Toggle("Incremental mode (paste as you speak)", isOn: $store.incrementalMode)
            }
            Section("Language") {
                Picker("Language", selection: $store.locale) {
                    ForEach(SpeechManager.supportedLocales.indices, id: \.self) { i in
                        Text(SpeechManager.supportedLocales[i].name).tag(SpeechManager.supportedLocales[i].id)
                    }
                }
            }
            Section("Microphone") {
                HStack {
                    Picker("Input", selection: $store.micID) {
                        if store.mics.isEmpty { Text("No microphones found").tag(AudioDeviceID(0)) }
                        ForEach(store.mics) { Text($0.name).tag($0.id) }
                    }
                    Button { store.speechManager?.refreshMicList(); store.objectWillChange.send() } label: {
                        Image(systemName: "arrow.clockwise")
                    }.help("Refresh microphone list")
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct ShortcutsTab: View {
    @ObservedObject var store: DictationSettingsStore
    var body: some View {
        Form {
            Section("Trigger key — hold to dictate, release to type") {
                KeycapKeyboard(store: store)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 4)
                Toggle("I'm using a non-Mac (PC) keyboard", isOn: $store.pcKeyboard)
                Text("Tap a key to toggle it; highlighted keys are active. Double-tap a trigger key while dictating to press Return. At least one key stays enabled.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
    }
}

private struct IndicatorTab: View {
    @ObservedObject var store: DictationSettingsStore
    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    DotPreview(store: store).frame(width: 48, height: 48)
                    VStack(alignment: .leading) {
                        Picker("Style", selection: $store.dotStyle) {
                            ForEach(DotStyle.allCases, id: \.self) { Text($0.title).tag($0) }
                        }
                        Picker("Speed", selection: $store.dotSpeed) {
                            ForEach(DotSpeed.allCases, id: \.self) { Text($0.title).tag($0) }
                        }
                    }
                }
                if store.dotStyle == .custom {
                    HStack { Text("Hue"); Slider(value: $store.customHue, in: 0...1) }
                }
                HStack { Text("Opacity \(Int(store.dotOpacity * 100))%"); Slider(value: $store.dotOpacity, in: 0.2...1) }
            }
            Section("Motion") {
                Toggle("Wave", isOn: $store.motionWave)
                Toggle("Spin", isOn: $store.motionSpin)
                Toggle("Ripple", isOn: $store.motionRipple)
                Toggle("Breathe", isOn: $store.motionBreathe)
            }
            Section("Floating mic") {
                HStack { Text("Icon size \(Int(store.iconSize))px"); Slider(value: $store.iconSize, in: 24...80, step: 2) }
                Toggle("Show microphone symbol", isOn: $store.showMicSymbol)
            }
        }
        .formStyle(.grouped)
    }
}

private struct CaptionsTab: View {
    @ObservedObject var store: DictationSettingsStore
    var body: some View {
        Form {
            Section {
                Toggle("Show live captions", isOn: $store.captionsEnabled)
            }
            Section("Placement") {
                Picker("Position", selection: $store.position) {
                    Text("Top").tag("top"); Text("Bottom").tag("bottom")
                }.pickerStyle(.segmented)
                Picker("Alignment", selection: $store.alignment) {
                    Text("Left").tag("left"); Text("Center").tag("center"); Text("Right").tag("right")
                }.pickerStyle(.segmented)
            }
            Section("Text") {
                HStack { Text("Size \(Int(store.fontSize))"); Slider(value: $store.fontSize, in: 14...72) }
                ColorPicker("Color", selection: $store.textColor, supportsOpacity: false)
                HStack { Text("Opacity"); Slider(value: $store.textOpacity, in: 0.2...1) }
            }
            Section("Background") {
                Toggle("Background box", isOn: $store.showBackground)
                if store.showBackground {
                    HStack { Text("Box opacity"); Slider(value: $store.backgroundOpacity, in: 0...1) }
                }
                Toggle("Window shadow", isOn: $store.showWindowShadow)
            }
        }
        .formStyle(.grouped)
    }
}

private struct BehaviorTab: View {
    @ObservedObject var store: DictationSettingsStore
    var body: some View {
        Form {
            Section("Clipboard") {
                Toggle("Clipboard cycling (hold ⌘, tap V to cycle history)", isOn: $store.clipboardCycling)
            }
            Section("While dictating") {
                Toggle("Pause media / mute sound", isOn: $store.pauseMediaEnabled)
                if store.pauseMediaEnabled {
                    Picker("Method", selection: $store.pauseMethod) {
                        Text("Pause media players").tag("pauseApps")
                        Text("Mute all sound").tag("muteSystem")
                    }
                    if store.pauseMethod == "pauseApps" {
                        ForEach(MediaController.commonApps, id: \.self) { app in
                            Toggle(app, isOn: Binding(
                                get: { store.pausedApps.contains(app) },
                                set: { on in
                                    if on { store.pausedApps.insert(app) } else { store.pausedApps.remove(app) }
                                }))
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

/// Owns the settings NSWindow so it survives and reuses a single instance.
final class SettingsWindowController {
    static let shared = SettingsWindowController()
    private var window: NSWindow?

    func show() {
        if window == nil {
            let host = NSHostingController(rootView: SettingsView(store: .shared))
            let win = NSWindow(contentViewController: host)
            win.title = "SimpleDictation Settings"
            win.styleMask = [.titled, .closable, .miniaturizable]
            win.isReleasedWhenClosed = false
            win.center()
            window = win
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
