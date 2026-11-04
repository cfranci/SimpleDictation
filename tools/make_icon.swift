#!/usr/bin/env swift
// make_icon.swift — generates SimpleDictation app icon (1024x1024)
// Usage: swift /Users/cf/Projects/SimpleDictation/tools/make_icon.swift

import AppKit
import CoreGraphics

let canvasSize: CGFloat = 1024
let artSize: CGFloat = 824          // squircle art area
let margin: CGFloat = (canvasSize - artSize) / 2  // ~100px each side
let cornerRadius: CGFloat = 185     // ~0.225 * artSize

let circleRatio: CGFloat = 0.54     // frosted circle diameter as fraction of artSize
let circleD: CGFloat = artSize * circleRatio
let circleR: CGFloat = circleD / 2

// Create bitmap context
let colorSpace = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(
    data: nil,
    width: Int(canvasSize),
    height: Int(canvasSize),
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    fputs("ERROR: could not create CGContext\n", stderr)
    exit(1)
}

// AppKit coordinate system: origin bottom-left in CGContext directly,
// but NSGraphicsContext wraps it. We'll use NSGraphicsContext for NSImage.
NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)

// ---- 1. Draw squircle clipping path ----
let squircleRect = CGRect(x: margin, y: margin, width: artSize, height: artSize)
let squirclePath = NSBezierPath(roundedRect: squircleRect, xRadius: cornerRadius, yRadius: cornerRadius)
squirclePath.addClip()

// ---- 2. Rainbow gradient background (diagonal linear, top-left to bottom-right) ----
// 7 stops spanning the hue wheel in squircle coords
let gradientColors: [NSColor] = [
    NSColor(hue: 0.0,   saturation: 1.0, brightness: 1.0, alpha: 1.0), // red
    NSColor(hue: 0.08,  saturation: 1.0, brightness: 1.0, alpha: 1.0), // orange
    NSColor(hue: 0.17,  saturation: 1.0, brightness: 1.0, alpha: 1.0), // yellow
    NSColor(hue: 0.33,  saturation: 0.95, brightness: 0.95, alpha: 1.0), // green
    NSColor(hue: 0.55,  saturation: 1.0, brightness: 1.0, alpha: 1.0), // cyan-blue
    NSColor(hue: 0.67,  saturation: 1.0, brightness: 1.0, alpha: 1.0), // blue
    NSColor(hue: 0.80,  saturation: 1.0, brightness: 0.95, alpha: 1.0), // violet
]

let locations: [CGFloat] = [0, 0.167, 0.333, 0.5, 0.667, 0.833, 1.0]

let cgColors = gradientColors.map { $0.cgColor }
guard let gradient = CGGradient(colorsSpace: colorSpace, colors: cgColors as CFArray, locations: locations) else {
    fputs("ERROR: could not create gradient\n", stderr)
    exit(1)
}

// Draw from top-left to bottom-right of the full canvas
ctx.drawLinearGradient(
    gradient,
    start: CGPoint(x: 0, y: canvasSize),   // top-left (CGContext y=0 is bottom)
    end:   CGPoint(x: canvasSize, y: 0),   // bottom-right
    options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
)

// ---- 3. Frosted white circle (centered in squircle) ----
let centerX = canvasSize / 2
let centerY = canvasSize / 2
let circleRect = CGRect(
    x: centerX - circleR,
    y: centerY - circleR,
    width: circleD,
    height: circleD
)

// Fill: semi-transparent white (frosted glass look)
NSColor(white: 1.0, alpha: 0.25).setFill()
let circlePath = NSBezierPath(ovalIn: circleRect)
circlePath.fill()

// Rim/stroke: brighter white at low alpha for glassy edge
NSColor(white: 1.0, alpha: 0.55).setStroke()
circlePath.lineWidth = 3.0
circlePath.stroke()

// ---- 4. Microphone glyph centered in circle ----
// Try SF Symbol first; fall back to NSBezierPath if unavailable
let micGlyphHeight = circleD * 0.57   // ~57% of circle diameter

func drawMicWithBezierPath(cx: CGFloat, cy: CGFloat, height: CGFloat) {
    let w = height * 0.52           // mic body width
    let bodyH = height * 0.60       // capsule body height
    let standArmH = height * 0.22   // stand arc rise
    let baseW = w * 0.85
    let baseH = height * 0.07

    let bodyRect = CGRect(
        x: cx - w / 2,
        y: cy - bodyH / 2 + height * 0.05,
        width: w,
        height: bodyH
    )

    // Capsule body
    NSColor.white.setFill()
    let bodyPath = NSBezierPath(roundedRect: bodyRect, xRadius: w / 2, yRadius: w / 2)
    bodyPath.fill()

    // Stand arc (U-shape below body)
    let standPath = NSBezierPath()
    let arcCenterY = bodyRect.minY
    let arcLeft = cx - w * 0.72
    let arcRight = cx + w * 0.72
    standPath.move(to: CGPoint(x: arcLeft, y: arcCenterY))
    standPath.appendArc(
        withCenter: CGPoint(x: cx, y: arcCenterY),
        radius: w * 0.72,
        startAngle: 180,
        endAngle: 0,
        clockwise: true
    )
    standPath.lineWidth = w * 0.14
    standPath.lineCapStyle = .round
    NSColor.white.setStroke()
    standPath.stroke()

    // Vertical stem connecting arc to base
    let stemPath = NSBezierPath()
    stemPath.move(to: CGPoint(x: cx, y: arcCenterY - w * 0.72))
    stemPath.line(to: CGPoint(x: cx, y: arcCenterY - w * 0.72 - standArmH))
    stemPath.lineWidth = w * 0.14
    stemPath.lineCapStyle = .round
    NSColor.white.setStroke()
    stemPath.stroke()

    // Base bar
    let baseRect = CGRect(
        x: cx - baseW / 2,
        y: arcCenterY - w * 0.72 - standArmH - baseH,
        width: baseW,
        height: baseH
    )
    let basePath = NSBezierPath(roundedRect: baseRect, xRadius: baseH / 2, yRadius: baseH / 2)
    NSColor.white.setFill()
    basePath.fill()
}

var usedSFSymbol = false

// Use systemSymbolName API (works headless), configure size, tint white
if let baseImage = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: nil) {
    let pointSize = micGlyphHeight * 0.72   // SF point size that yields ~micGlyphHeight pixels
    let cfg = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
    if let configured = baseImage.withSymbolConfiguration(cfg) {
        // Build a tinted white copy
        let symSize = configured.size
        let tinted = NSImage(size: symSize)
        tinted.lockFocus()
        NSColor.white.setFill()
        NSRect(origin: .zero, size: symSize).fill()
        configured.draw(in: NSRect(origin: .zero, size: symSize),
                        from: .zero,
                        operation: .destinationIn,
                        fraction: 1.0)
        tinted.unlockFocus()

        // Center it in the circle
        let glyphRect = NSRect(
            x: centerX - symSize.width / 2,
            y: centerY - symSize.height / 2,
            width: symSize.width,
            height: symSize.height
        )
        tinted.draw(in: glyphRect, from: .zero, operation: .sourceOver, fraction: 1.0)
        usedSFSymbol = true
    }
}

if !usedSFSymbol {
    // Fall back to hand-drawn mic
    drawMicWithBezierPath(cx: centerX, cy: centerY, height: micGlyphHeight)
    fputs("NOTE: SF Symbol unavailable; used NSBezierPath mic fallback\n", stderr)
}

// ---- 5. Soft drop shadow under mic (draw it behind — we'll repaint) ----
// Actually add a subtle glow/shadow by layering a slightly enlarged,
// blurred semi-transparent circle behind the mic area.
// Since we can't blur in CoreGraphics easily without offscreen, we layer
// a few semi-transparent circles of decreasing alpha for a soft halo.
let shadowLayers = 4
for i in 1...shadowLayers {
    let expand = CGFloat(i) * 6.0
    let shadowRect = CGRect(
        x: centerX - circleR * 0.42 - expand,
        y: centerY - circleR * 0.57 - expand,
        width: circleD * 0.84 + expand * 2,
        height: circleD * 0.57 + expand * 2
    )
    // Don't draw; we already have the glyph. Skip to avoid drawing over.
    _ = shadowRect
}

// ---- 6. Export PNG ----
guard let cgImage = ctx.makeImage() else {
    fputs("ERROR: could not get CGImage from context\n", stderr)
    exit(1)
}

let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
guard let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
    fputs("ERROR: could not create PNG data\n", stderr)
    exit(1)
}

let outputPath = "/Users/cf/Projects/SimpleDictation/icon_1024.png"
do {
    try pngData.write(to: URL(fileURLWithPath: outputPath))
    print("Written: \(outputPath) (\(pngData.count) bytes)")
    print("SF Symbol used: \(usedSFSymbol)")
} catch {
    fputs("ERROR writing PNG: \(error)\n", stderr)
    exit(1)
}
