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
    /// "hold" (hold key to talk) or "toggle" (triple-tap start, single-tap stop, double-tap Return).
    @Published var triggerMode: String { didSet { UserDefaults.standard.set(triggerMode, forKey: "triggerMode") } }

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
        triggerMode = d.string(forKey: "triggerMode") ?? "hold"

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

// MARK: - Stepped settings (one major setting per page)

enum SettingPageID: String, CaseIterable, Identifiable {
    case engine, microphone, language
    case triggerMode, triggerKeys
    case indicator, captions
    case incremental, clipboard, media

    var id: String { rawValue }

    var title: String {
        switch self {
        case .engine:       return "Engine"
        case .microphone:   return "Microphone"
        case .language:     return "Language"
        case .triggerMode:  return "Trigger mode"
        case .triggerKeys:  return "Trigger keys"
        case .indicator:    return "Indicator"
        case .captions:     return "Captions"
        case .incremental:  return "Paste as you speak"
        case .clipboard:    return "Clipboard cycling"
        case .media:        return "Pause media"
        }
    }

    var icon: String {
        switch self {
        case .engine:       return "cpu"
        case .microphone:   return "mic.fill"
        case .language:     return "globe"
        case .triggerMode:  return "hand.tap.fill"
        case .triggerKeys:  return "keyboard"
        case .indicator:    return "circle.hexagongrid.fill"
        case .captions:     return "captions.bubble.fill"
        case .incremental:  return "text.cursor"
        case .clipboard:    return "doc.on.clipboard.fill"
        case .media:        return "speaker.slash.fill"
        }
    }
}

/// A selectable, explained option row (radio-style) for one-of-N choices.
struct OptionCard: View {
    let title: String
    let description: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(selected ? Color.accentColor : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.callout.weight(.medium))
                    Text(description).font(.caption2).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8)
                .fill(selected ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.03)))
            .overlay(RoundedRectangle(cornerRadius: 8)
                .stroke(selected ? Color.accentColor.opacity(0.5) : Color.clear, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// A clean, centered page that explains and hosts exactly one setting.
struct SettingPage<Content: View>: View {
    let icon: String
    let title: String
    let subtitle: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 20)
            Image(systemName: icon)
                .font(.system(size: 40, weight: .regular))
                .foregroundStyle(Color.accentColor)
            Text(title).font(.system(size: 26, weight: .bold))
                .multilineTextAlignment(.center)
            Text(subtitle)
                .font(.callout).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)
                .fixedSize(horizontal: false, vertical: true)
            content
                .frame(maxWidth: 460)
                .padding(.top, 8)
            Spacer(minLength: 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 36)
    }
}

struct SettingsView: View {
    @ObservedObject var store: DictationSettingsStore
    @State private var selection: SettingPageID? = .engine
    @State private var showLargeModels = false

    private let order = SettingPageID.allCases
    private let groups: [(String, [SettingPageID])] = [
        ("Recognition", [.engine, .microphone, .language]),
        ("Input", [.triggerMode, .triggerKeys]),
        ("Feedback", [.indicator, .captions]),
        ("Extras", [.incremental, .clipboard, .media]),
    ]

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            VStack(spacing: 0) {
                page(selection ?? .engine)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                stepBar
            }
        }
        .frame(width: 780, height: 560)
        .onAppear { store.speechManager?.refreshMicList() }
    }

    private var sidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(groups, id: \.0) { group in
                    Text(group.0.uppercased())
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 2)
                    ForEach(group.1) { id in sidebarRow(id) }
                }
            }
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 208)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func sidebarRow(_ id: SettingPageID) -> some View {
        let isSel = (selection ?? .engine) == id
        return Button { selection = id } label: {
            HStack(spacing: 9) {
                Image(systemName: id.icon)
                    .frame(width: 18)
                    .foregroundStyle(isSel ? Color.accentColor : .secondary)
                Text(id.title)
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 6)
                .fill(isSel ? Color.accentColor.opacity(0.20) : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
    }

    private var stepBar: some View {
        let sel = selection ?? .engine
        let idx = order.firstIndex(of: sel) ?? 0
        return HStack {
            Button { if idx > 0 { selection = order[idx - 1] } } label: {
                Label("Previous", systemImage: "chevron.left")
            }.disabled(idx == 0)
            Spacer()
            Text("\(idx + 1) of \(order.count)").font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button { if idx < order.count - 1 { selection = order[idx + 1] } } label: {
                Label("Next", systemImage: "chevron.right").labelStyle(.titleAndIcon)
            }.disabled(idx == order.count - 1)
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
    }

    @ViewBuilder
    private func page(_ id: SettingPageID) -> some View {
        switch id {
        case .engine:
            SettingPage(icon: id.icon, title: "Dictation engine",
                        subtitle: "The on-device model that turns your voice into text. Your audio never leaves your Mac.") {
                VStack(spacing: 10) {
                    ScrollView { EngineChooser(store: store, showLarge: $showLargeModels) }
                        .frame(maxHeight: 300)
                    if #available(macOS 14, *) {
                        Toggle("Keep only the selected model (reclaim disk)", isOn: $store.keepOnlyModel)
                            .font(.callout)
                    }
                }
            }
        case .microphone:
            SettingPage(icon: id.icon, title: "Microphone",
                        subtitle: "Choose which microphone to listen to while you dictate.") {
                HStack {
                    Picker("", selection: $store.micID) {
                        if store.mics.isEmpty { Text("No microphones found").tag(AudioDeviceID(0)) }
                        ForEach(store.mics) { Text($0.name).tag($0.id) }
                    }.labelsHidden()
                    Button { store.speechManager?.refreshMicList(); store.objectWillChange.send() } label: {
                        Image(systemName: "arrow.clockwise")
                    }.help("Refresh microphone list")
                }
            }
        case .language:
            SettingPage(icon: id.icon, title: "Language",
                        subtitle: "The language you'll speak in.") {
                Picker("", selection: $store.locale) {
                    ForEach(SpeechManager.supportedLocales.indices, id: \.self) { i in
                        Text(SpeechManager.supportedLocales[i].name).tag(SpeechManager.supportedLocales[i].id)
                    }
                }.labelsHidden()
            }
        case .triggerMode:
            SettingPage(icon: id.icon, title: "Trigger mode",
                        subtitle: "How you start and stop dictation.") {
                VStack(spacing: 8) {
                    OptionCard(title: "Hold to talk",
                               description: "Hold a trigger key while you speak, release to type. Double-tap for Return.",
                               selected: store.triggerMode == "hold") { store.triggerMode = "hold" }
                    OptionCard(title: "Hands-free",
                               description: "Triple-tap a trigger key to start listening, single tap to stop, double-tap for Return.",
                               selected: store.triggerMode == "toggle") { store.triggerMode = "toggle" }
                }
            }
        case .triggerKeys:
            SettingPage(icon: id.icon, title: "Trigger keys",
                        subtitle: "Tap a key to turn it on or off. Highlighted keys start dictation. At least one stays on.") {
                VStack(spacing: 14) {
                    KeycapKeyboard(store: store)
                    Toggle("I'm using a non-Mac (PC) keyboard", isOn: $store.pcKeyboard).font(.callout)
                }
            }
        case .indicator:
            SettingPage(icon: id.icon, title: "Recording indicator",
                        subtitle: "How the floating mic looks while you dictate.") {
                ScrollView {
                    VStack(spacing: 12) {
                        DotPreview(store: store).frame(width: 56, height: 56)
                        Picker("Style", selection: $store.dotStyle) {
                            ForEach(DotStyle.allCases, id: \.self) { Text($0.title).tag($0) }
                        }
                        Picker("Speed", selection: $store.dotSpeed) {
                            ForEach(DotSpeed.allCases, id: \.self) { Text($0.title).tag($0) }
                        }
                        if store.dotStyle == .custom {
                            HStack { Text("Hue"); Slider(value: $store.customHue, in: 0...1) }
                        }
                        HStack { Text("Opacity \(Int(store.dotOpacity * 100))%"); Slider(value: $store.dotOpacity, in: 0.2...1) }
                        HStack { Text("Size \(Int(store.iconSize))px"); Slider(value: $store.iconSize, in: 24...80, step: 2) }
                        HStack(spacing: 14) {
                            Toggle("Wave", isOn: $store.motionWave)
                            Toggle("Spin", isOn: $store.motionSpin)
                            Toggle("Ripple", isOn: $store.motionRipple)
                            Toggle("Breathe", isOn: $store.motionBreathe)
                        }.toggleStyle(.checkbox).font(.caption)
                        Toggle("Show microphone symbol", isOn: $store.showMicSymbol).font(.callout)
                    }
                }.frame(maxHeight: 330)
            }
        case .captions:
            SettingPage(icon: id.icon, title: "Live captions",
                        subtitle: "See your words on screen as you speak.") {
                ScrollView {
                    VStack(spacing: 12) {
                        Toggle("Show live captions", isOn: $store.captionsEnabled)
                        if store.captionsEnabled {
                            Picker("Position", selection: $store.position) {
                                Text("Top").tag("top"); Text("Bottom").tag("bottom")
                            }.pickerStyle(.segmented)
                            Picker("Alignment", selection: $store.alignment) {
                                Text("Left").tag("left"); Text("Center").tag("center"); Text("Right").tag("right")
                            }.pickerStyle(.segmented)
                            HStack { Text("Size \(Int(store.fontSize))"); Slider(value: $store.fontSize, in: 14...72) }
                            ColorPicker("Color", selection: $store.textColor, supportsOpacity: false)
                            HStack { Text("Opacity"); Slider(value: $store.textOpacity, in: 0.2...1) }
                            Toggle("Background box", isOn: $store.showBackground)
                            if store.showBackground {
                                HStack { Text("Box opacity"); Slider(value: $store.backgroundOpacity, in: 0...1) }
                            }
                            Toggle("Window shadow", isOn: $store.showWindowShadow)
                        }
                    }
                }.frame(maxHeight: 330)
            }
        case .incremental:
            SettingPage(icon: id.icon, title: "Paste as you speak",
                        subtitle: "In Hands-free mode, type words as you talk — refreshing every few seconds — instead of all at once when you finish.") {
                VStack(spacing: 10) {
                    Toggle("Paste as you speak", isOn: $store.incrementalMode).toggleStyle(.switch)
                    if store.incrementalMode && store.triggerMode != "toggle" {
                        Label("Needs Hands-free trigger mode. In Hold-to-talk your text is still pasted when you release — holding a key while live-typing would duplicate/garble it.",
                              systemImage: "info.circle")
                            .font(.caption).foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        case .clipboard:
            SettingPage(icon: id.icon, title: "Clipboard cycling",
                        subtitle: "After you paste, hold ⌘ and tap V again to cycle back through earlier clipboard items.") {
                Toggle("Enable clipboard cycling", isOn: $store.clipboardCycling).toggleStyle(.switch)
            }
        case .media:
            SettingPage(icon: id.icon, title: "Pause media",
                        subtitle: "Pause your music or mute all sound while you dictate, then restore it after.") {
                VStack(spacing: 12) {
                    Toggle("Pause media / mute sound while dictating", isOn: $store.pauseMediaEnabled)
                    if store.pauseMediaEnabled {
                        Picker("Method", selection: $store.pauseMethod) {
                            Text("Pause media players").tag("pauseApps")
                            Text("Mute all sound").tag("muteSystem")
                        }.pickerStyle(.segmented)
                        if store.pauseMethod == "pauseApps" {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(MediaController.commonApps, id: \.self) { app in
                                    Toggle(app, isOn: Binding(
                                        get: { store.pausedApps.contains(app) },
                                        set: { on in
                                            if on { store.pausedApps.insert(app) } else { store.pausedApps.remove(app) }
                                        }))
                                }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
        }
    }
}

/// Places a window centered on the screen that currently has the mouse cursor,
/// clamped to its visible area — so it never opens off-screen or on an inactive
/// display (NSWindow.center() can land on the wrong screen in multi-monitor setups).
func placeWindowOnActiveScreen(_ win: NSWindow, fallbackSize: NSSize) {
    var size = win.frame.size
    if size.width < 100 || size.height < 100 { size = fallbackSize }
    let mouse = NSEvent.mouseLocation
    let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
        ?? NSScreen.main ?? NSScreen.screens.first
    guard let vf = screen?.visibleFrame else { win.center(); return }
    let x = vf.midX - size.width / 2
    let y = vf.midY - size.height / 2
    win.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
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
            window = win
        }
        if let win = window { placeWindowOnActiveScreen(win, fallbackSize: NSSize(width: 780, height: 592)) }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
