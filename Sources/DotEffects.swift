import Cocoa

/// Color families for the recording indicator, ported from MenuBarBuddy.
/// Every style renders through the same animated two-tone engine.
enum DotStyle: String, CaseIterable {
    case classic, rainbow, ocean, lava, aurora, custom

    var title: String {
        switch self {
        case .classic: return "Classic Red"
        case .rainbow: return "Rainbow"
        case .ocean:   return "Ocean"
        case .lava:    return "Lava"
        case .aurora:  return "Aurora"
        case .custom:  return "Custom Color…"
        }
    }

    /// (baseHue, drift range, top→bottom hue offset). Rainbow ignores these and
    /// cycles the full wheel; custom substitutes the user's hue.
    var palette: (base: CGFloat, drift: CGFloat, offset: CGFloat) {
        switch self {
        case .ocean:  return (0.55, 0.07, 0.10)
        case .lava:   return (0.02, 0.05, 0.09)
        case .aurora: return (0.38, 0.08, 0.34)
        default:      return (0.45, 0.00, 0.33)
        }
    }
}

/// How the two tones move inside the dot. Motions LAYER — any combination.
enum DotMotion: String, CaseIterable {
    case wave, ripple, spin, breathe, steady

    var title: String {
        switch self {
        case .wave:    return "Wave"
        case .ripple:  return "Ripple"
        case .spin:    return "Spin"
        case .breathe: return "Breathe"
        case .steady:  return "Steady"
        }
    }
}

enum DotSpeed: String, CaseIterable {
    case slow, normal, fast
    var title: String { rawValue.capitalized }
    var multiplier: CGFloat {
        switch self {
        case .slow: return 0.5
        case .normal: return 1.0
        case .fast: return 2.0
        }
    }
}

/// Renders the animated multicolor recording indicator.
enum DotEffect {
    private static func hue(_ h: CGFloat, _ s: CGFloat = 0.9, _ b: CGFloat = 1.0) -> NSColor {
        var hh = h.truncatingRemainder(dividingBy: 1)
        if hh < 0 { hh += 1 }
        return NSColor(hue: hh, saturation: s, brightness: b, alpha: 1)
    }

    /// Top and bottom tone for a style at a given animation phase.
    static func colors(style: DotStyle, phase: CGFloat, customHue: CGFloat) -> (NSColor, NSColor) {
        switch style {
        case .classic:
            return (NSColor(red: 1.0, green: 0.23, blue: 0.19, alpha: 1),
                    NSColor(red: 0.80, green: 0.10, blue: 0.10, alpha: 1))
        case .rainbow:
            let h = phase / (2 * .pi)
            return (hue(h), hue(h + 0.5))
        case .custom:
            return (hue(customHue), hue(customHue + 0.12))
        default:
            let p = style.palette
            let base = p.base + p.drift * sin(phase * 0.5)
            return (hue(base), hue(base + p.offset))
        }
    }

    /// A `size`×`size` circle filled with the animated two-tone gradient.
    /// Rendered per-pixel into a retina bitmap (cheap at these sizes).
    static func image(style: DotStyle, motions: Set<DotMotion>, phase: CGFloat,
                      customHue: CGFloat, size: CGFloat, scale: CGFloat = 2) -> NSImage? {
        let (topColor, bottomColor) = colors(style: style, phase: phase, customHue: customHue)
        let px = max(2, Int(size * scale))
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                         isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0),
              let top = topColor.usingColorSpace(.deviceRGB),
              let bottom = bottomColor.usingColorSpace(.deviceRGB),
              let bytes = rep.bitmapData else { return nil }

        let center = CGFloat(px) / 2
        var dotRadius = center - scale                 // fill the circle, leave a 1px rim
        if motions.contains(.breathe) {
            dotRadius *= 0.90 + 0.10 * sin(phase)
        }
        let amplitude = dotRadius * 0.35
        let blendBand = dotRadius * 0.9
        let bpr = rep.bytesPerRow
        let (tr, tg, tb) = (top.redComponent, top.greenComponent, top.blueComponent)
        let (br, bg, bb) = (bottom.redComponent, bottom.greenComponent, bottom.blueComponent)

        for y in 0..<px {
            for x in 0..<px {
                let dx = CGFloat(x) + 0.5 - center
                let dy = CGFloat(y) + 0.5 - center
                let dist = (dx * dx + dy * dy).squareRoot()
                let alpha = max(0, min(1, dotRadius - dist + 0.5))
                let off = y * bpr + x * 4
                if alpha <= 0 {
                    bytes[off] = 0; bytes[off+1] = 0; bytes[off+2] = 0; bytes[off+3] = 0
                    continue
                }
                var comps: [CGFloat] = []
                if motions.contains(.wave) {
                    let wave = amplitude * sin((dx / dotRadius) * .pi * 1.4 + phase)
                    var tw = (dy - wave) / blendBand + 0.5
                    tw = max(0, min(1, tw))
                    comps.append(tw * tw * (3 - 2 * tw))
                }
                if motions.contains(.ripple) {
                    comps.append(0.5 + 0.5 * sin((dist / dotRadius) * .pi * 2.2 - phase * 2))
                }
                if motions.contains(.spin) {
                    comps.append(0.5 + 0.5 * sin(atan2(dy, dx) + phase))
                }
                if motions.contains(.steady) {
                    var ts = dy / blendBand + 0.5
                    ts = max(0, min(1, ts))
                    comps.append(ts * ts * (3 - 2 * ts))
                }
                let t = comps.isEmpty ? 0 : comps.reduce(0, +) / CGFloat(comps.count)
                let r = tr + (br - tr) * t
                let g = tg + (bg - tg) * t
                let b = tb + (bb - tb) * t
                bytes[off]   = UInt8(max(0, min(255, r * alpha * 255)))
                bytes[off+1] = UInt8(max(0, min(255, g * alpha * 255)))
                bytes[off+2] = UInt8(max(0, min(255, b * alpha * 255)))
                bytes[off+3] = UInt8(max(0, min(255, alpha * 255)))
            }
        }
        let img = NSImage(size: NSSize(width: size, height: size))
        img.addRepresentation(rep)
        return img
    }
}

/// Persisted appearance settings for the recording indicator, shared by the
/// floating mic view and the Settings window.
enum DotSettings {
    static var style: DotStyle {
        get { DotStyle(rawValue: UserDefaults.standard.string(forKey: "dotStyle") ?? "") ?? .rainbow }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "dotStyle") }
    }
    static var motions: Set<DotMotion> {
        get {
            guard let raw = UserDefaults.standard.string(forKey: "dotMotion") else { return [.wave, .spin] }
            let set = Set(raw.split(separator: ",").compactMap { DotMotion(rawValue: String($0)) })
            return set.isEmpty && raw.isEmpty ? [] : (set.isEmpty ? [.wave, .spin] : set)
        }
        set { UserDefaults.standard.set(newValue.map(\.rawValue).sorted().joined(separator: ","), forKey: "dotMotion") }
    }
    static var speed: DotSpeed {
        get { DotSpeed(rawValue: UserDefaults.standard.string(forKey: "dotSpeed") ?? "") ?? .normal }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "dotSpeed") }
    }
    static var customHue: CGFloat {
        get {
            let v = UserDefaults.standard.object(forKey: "customDotHue") as? Double
            return CGFloat(v ?? 0.6)
        }
        set { UserDefaults.standard.set(Double(newValue), forKey: "customDotHue") }
    }
    /// Whether to draw the microphone glyph on the floating button.
    static var showMicSymbol: Bool {
        get { UserDefaults.standard.object(forKey: "showMicSymbol") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "showMicSymbol") }
    }
}

extension NSColor {
    var hexString: String {
        guard let c = usingColorSpace(.deviceRGB) else { return "#FFFFFF" }
        let r = Int(round(c.redComponent * 255))
        let g = Int(round(c.greenComponent * 255))
        let b = Int(round(c.blueComponent * 255))
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    convenience init?(hexString: String) {
        var s = hexString.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = Int(s, radix: 16) else { return nil }
        self.init(red: CGFloat((v >> 16) & 0xFF) / 255,
                  green: CGFloat((v >> 8) & 0xFF) / 255,
                  blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }
}
