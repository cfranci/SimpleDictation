import SwiftUI

/// Bridges the app's UserDefaults-backed settings to SwiftUI. Each property
/// writes through to the live controllers (DotSettings / CaptionOverlayController)
/// so changes apply immediately. Property observers do not fire during init,
/// so the initial loads below don't cause side effects.
final class DictationSettingsStore: ObservableObject {
    static let shared = DictationSettingsStore()
    private let cap = CaptionOverlayController.shared

    // Recording indicator
    @Published var dotStyle: DotStyle { didSet { DotSettings.style = dotStyle } }
    @Published var dotSpeed: DotSpeed { didSet { DotSettings.speed = dotSpeed } }
    @Published var customHue: Double { didSet { DotSettings.customHue = CGFloat(customHue) } }
    @Published var motionWave: Bool    { didSet { setMotion(.wave, motionWave) } }
    @Published var motionSpin: Bool    { didSet { setMotion(.spin, motionSpin) } }
    @Published var motionRipple: Bool  { didSet { setMotion(.ripple, motionRipple) } }
    @Published var motionBreathe: Bool { didSet { setMotion(.breathe, motionBreathe) } }

    // Microphone
    @Published var showMicSymbol: Bool { didSet { DotSettings.showMicSymbol = showMicSymbol } }

    // Captions
    @Published var captionsEnabled: Bool { didSet { cap.enabled = captionsEnabled } }
    @Published var position: String       { didSet { cap.position = position; cap.preview() } }
    @Published var alignment: String      { didSet { cap.alignment = alignment; cap.preview() } }
    @Published var fontSize: Double        { didSet { cap.fontSize = CGFloat(fontSize); cap.preview() } }
    @Published var textColor: Color        { didSet { cap.textColor = NSColor(textColor); cap.preview() } }
    @Published var textOpacity: Double      { didSet { cap.textOpacity = textOpacity; cap.preview() } }
    @Published var showBackground: Bool     { didSet { cap.showBackground = showBackground; cap.preview() } }
    @Published var backgroundOpacity: Double { didSet { cap.backgroundOpacity = backgroundOpacity; cap.preview() } }
    @Published var showWindowShadow: Bool   { didSet { cap.showWindowShadow = showWindowShadow; cap.preview() } }

    private func setMotion(_ m: DotMotion, _ on: Bool) {
        var s = DotSettings.motions
        if on { s.insert(m) } else { s.remove(m) }
        DotSettings.motions = s
    }

    init() {
        dotStyle = DotSettings.style
        dotSpeed = DotSettings.speed
        customHue = Double(DotSettings.customHue)
        let motions = DotSettings.motions
        motionWave = motions.contains(.wave)
        motionSpin = motions.contains(.spin)
        motionRipple = motions.contains(.ripple)
        motionBreathe = motions.contains(.breathe)
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
    }
}

/// A small live-animated preview of the recording dot with the current style.
private struct DotPreview: View {
    @ObservedObject var store: DictationSettingsStore
    var body: some View {
        TimelineView(.animation) { timeline in
            let phase = timeline.date.timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: .pi * 2) * Double(store.dotSpeed.multiplier)
            let motions = currentMotions()
            if let img = DotEffect.image(style: store.dotStyle, motions: motions,
                                         phase: CGFloat(phase), customHue: CGFloat(store.customHue),
                                         size: 44) {
                Image(nsImage: img).resizable().frame(width: 44, height: 44)
            } else {
                Circle().fill(.red).frame(width: 44, height: 44)
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

struct SettingsView: View {
    @ObservedObject var store: DictationSettingsStore

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text("SimpleDictation")
                    .font(.title2.bold())

                GroupBox("Recording Indicator") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 14) {
                            DotPreview(store: store)
                            VStack(alignment: .leading, spacing: 6) {
                                Picker("Style", selection: $store.dotStyle) {
                                    ForEach(DotStyle.allCases, id: \.self) { Text($0.title).tag($0) }
                                }
                                Picker("Speed", selection: $store.dotSpeed) {
                                    ForEach(DotSpeed.allCases, id: \.self) { Text($0.title).tag($0) }
                                }
                            }
                        }
                        if store.dotStyle == .custom {
                            HStack {
                                Text("Hue")
                                Slider(value: $store.customHue, in: 0...1)
                            }
                        }
                        Divider()
                        Text("Motion").font(.caption).foregroundStyle(.secondary)
                        HStack {
                            Toggle("Wave", isOn: $store.motionWave)
                            Toggle("Spin", isOn: $store.motionSpin)
                        }
                        HStack {
                            Toggle("Ripple", isOn: $store.motionRipple)
                            Toggle("Breathe", isOn: $store.motionBreathe)
                        }
                    }.padding(.vertical, 4)
                }

                GroupBox("Microphone") {
                    Toggle("Show microphone symbol", isOn: $store.showMicSymbol)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                }

                GroupBox("Captions") {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("Show live captions", isOn: $store.captionsEnabled)
                        Picker("Position", selection: $store.position) {
                            Text("Top").tag("top"); Text("Bottom").tag("bottom")
                        }.pickerStyle(.segmented)
                        Picker("Alignment", selection: $store.alignment) {
                            Text("Left").tag("left"); Text("Center").tag("center"); Text("Right").tag("right")
                        }.pickerStyle(.segmented)
                        HStack {
                            Text("Size \(Int(store.fontSize))")
                            Slider(value: $store.fontSize, in: 14...72)
                        }
                        HStack {
                            ColorPicker("Text color", selection: $store.textColor, supportsOpacity: false)
                        }
                        HStack {
                            Text("Text opacity")
                            Slider(value: $store.textOpacity, in: 0.2...1)
                        }
                        Divider()
                        Toggle("Background box", isOn: $store.showBackground)
                        if store.showBackground {
                            HStack {
                                Text("Box opacity")
                                Slider(value: $store.backgroundOpacity, in: 0...1)
                            }
                        }
                        Toggle("Window shadow", isOn: $store.showWindowShadow)
                    }.padding(.vertical, 4)
                }
            }
            .padding(20)
        }
        .frame(width: 380, height: 640)
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
