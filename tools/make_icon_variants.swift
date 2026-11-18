#!/usr/bin/env swift
// make_icon_variants.swift — generates 6 distinct app icon variants for SimpleDictation
// Usage: swift /Users/cf/Projects/SimpleDictation/tools/make_icon_variants.swift
//
// Output: /Users/cf/Projects/SimpleDictation/tools/icon-variants/variant{1-6}-*.png

import AppKit
import CoreGraphics
import Foundation

let canvasSize: CGFloat = 1024
let artSize: CGFloat = 824
let margin: CGFloat = (canvasSize - artSize) / 2
let cornerRadius: CGFloat = 185

let circleRatio: CGFloat = 0.54
let circleD: CGFloat = artSize * circleRatio
let circleR: CGFloat = circleD / 2
let centerX = canvasSize / 2
let centerY = canvasSize / 2

let outputDir = "/Users/cf/Projects/SimpleDictation/tools/icon-variants"

// MARK: - Helpers

func makeContext() -> CGContext {
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
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
    return ctx
}

func clipToSquircle(ctx: CGContext) {
    let squircleRect = CGRect(x: margin, y: margin, width: artSize, height: artSize)
    let squirclePath = NSBezierPath(roundedRect: squircleRect, xRadius: cornerRadius, yRadius: cornerRadius)
    squirclePath.addClip()
}

func savePNG(ctx: CGContext, filename: String) {
    guard let cgImage = ctx.makeImage() else {
        fputs("ERROR: could not get CGImage for \(filename)\n", stderr)
        return
    }
    let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
    guard let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
        fputs("ERROR: could not create PNG for \(filename)\n", stderr)
        return
    }
    let path = "\(outputDir)/\(filename)"
    do {
        try pngData.write(to: URL(fileURLWithPath: path))
        print("Written: \(path)")
    } catch {
        fputs("ERROR writing \(path): \(error)\n", stderr)
    }
}

/// Draw the mic.fill SF Symbol (white, centered in circle). Falls back to NSBezierPath.
func drawMicGlyph(cx: CGFloat, cy: CGFloat) {
    let micGlyphHeight = circleD * 0.57

    if let baseImage = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: nil) {
        let pointSize = micGlyphHeight * 0.72
        let cfg = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
        if let configured = baseImage.withSymbolConfiguration(cfg) {
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
            let glyphRect = NSRect(
                x: cx - symSize.width / 2,
                y: cy - symSize.height / 2,
                width: symSize.width,
                height: symSize.height
            )
            tinted.draw(in: glyphRect, from: .zero, operation: .sourceOver, fraction: 1.0)
            return
        }
    }
    // Fallback bezier mic
    fputs("NOTE: SF Symbol unavailable, using NSBezierPath fallback\n", stderr)
    let w = micGlyphHeight * 0.52
    let bodyH = micGlyphHeight * 0.60
    let bodyRect = CGRect(x: cx - w/2, y: cy - bodyH/2 + micGlyphHeight*0.05, width: w, height: bodyH)
    NSColor.white.setFill()
    NSBezierPath(roundedRect: bodyRect, xRadius: w/2, yRadius: w/2).fill()
    let standPath = NSBezierPath()
    standPath.move(to: CGPoint(x: cx - w*0.72, y: bodyRect.minY))
    standPath.appendArc(withCenter: CGPoint(x: cx, y: bodyRect.minY), radius: w*0.72,
                        startAngle: 180, endAngle: 0, clockwise: true)
    standPath.lineWidth = w * 0.14
    standPath.lineCapStyle = .round
    NSColor.white.setStroke()
    standPath.stroke()
}

/// Draw the waveform SF Symbol (white, centered). Falls back to vertical bars.
func drawWaveformGlyph(cx: CGFloat, cy: CGFloat, size: CGFloat) {
    if let baseImage = NSImage(systemSymbolName: "waveform", accessibilityDescription: nil) {
        let pointSize = size * 0.65
        let cfg = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .medium)
        if let configured = baseImage.withSymbolConfiguration(cfg) {
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
            let glyphRect = NSRect(
                x: cx - symSize.width/2,
                y: cy - symSize.height/2 - size*0.08,
                width: symSize.width,
                height: symSize.height
            )
            tinted.draw(in: glyphRect, from: .zero, operation: .sourceOver, fraction: 1.0)
            return
        }
    }
    // Fallback: vertical bars
    fputs("NOTE: waveform SF Symbol unavailable, using bars fallback\n", stderr)
    let barW: CGFloat = size * 0.045
    let heights: [CGFloat] = [0.25, 0.45, 0.75, 1.0, 0.75, 0.45, 0.25]
    let totalW = CGFloat(heights.count) * barW + CGFloat(heights.count - 1) * barW * 0.6
    let startX = cx - totalW / 2
    NSColor.white.setFill()
    for (i, h) in heights.enumerated() {
        let bh = size * 0.5 * h
        let bx = startX + CGFloat(i) * barW * 1.6
        let by = cy - bh / 2
        let barRect = CGRect(x: bx, y: by, width: barW, height: bh)
        NSBezierPath(roundedRect: barRect, xRadius: barW/2, yRadius: barW/2).fill()
    }
}

/// Standard frosted circle + white rim
func drawFrostedCircle(cx: CGFloat, cy: CGFloat, alpha: CGFloat = 0.25) {
    let circleRect = CGRect(x: cx - circleR, y: cy - circleR, width: circleD, height: circleD)
    NSColor(white: 1.0, alpha: alpha).setFill()
    let circlePath = NSBezierPath(ovalIn: circleRect)
    circlePath.fill()
    NSColor(white: 1.0, alpha: 0.55).setStroke()
    circlePath.lineWidth = 3.0
    circlePath.stroke()
}

// Rainbow hue stops shared across variants
let rainbowHues: [CGFloat] = [0.0, 0.08, 0.17, 0.33, 0.55, 0.67, 0.80]
let rainbowLocations: [CGFloat] = [0, 0.167, 0.333, 0.5, 0.667, 0.833, 1.0]

func rainbowCGColors(saturation: CGFloat = 1.0, brightness: CGFloat = 1.0) -> [CGColor] {
    return rainbowHues.map { NSColor(hue: $0, saturation: saturation, brightness: brightness, alpha: 1.0).cgColor }
}

// MARK: - Variant 1: Conic/angular rainbow sweep (color-wheel look) + frosted circle + white mic

func makeVariant1() {
    let ctx = makeContext()
    clipToSquircle(ctx: ctx)

    // Fill background dark first
    NSColor.black.setFill()
    NSBezierPath(rect: CGRect(x: 0, y: 0, width: canvasSize, height: canvasSize)).fill()

    // Draw conic-like rainbow using pie wedges for each hue segment
    let numSegments = 360
    let segAngle = 2.0 * Double.pi / Double(numSegments)

    for i in 0..<numSegments {
        let angle = Double(i) * segAngle
        let hue = CGFloat(i) / CGFloat(numSegments)
        // Slightly desaturate at edges for a polished look
        let sat: CGFloat = 0.85 + 0.15 * abs(sin(CGFloat(i) * .pi / 180.0))
        NSColor(hue: hue, saturation: sat, brightness: 0.95, alpha: 1.0).setFill()

        let path = NSBezierPath()
        path.move(to: CGPoint(x: centerX, y: centerY))
        let startA = CGFloat(angle)
        let endA = CGFloat(angle + segAngle + 0.005) // tiny overlap to avoid gaps
        // Convert from math angles to NSBezierPath convention
        path.appendArc(withCenter: CGPoint(x: centerX, y: centerY),
                       radius: artSize * 0.72,
                       startAngle: startA * 180.0 / .pi,
                       endAngle: endA * 180.0 / .pi,
                       clockwise: false)
        path.close()
        path.fill()
    }

    // Dark vignette toward edges for depth
    let vignette = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [
            NSColor(white: 0, alpha: 0).cgColor,
            NSColor(white: 0, alpha: 0.38).cgColor
        ] as CFArray,
        locations: [0.55, 1.0]
    )!
    ctx.drawRadialGradient(vignette,
                           startCenter: CGPoint(x: centerX, y: centerY), startRadius: 0,
                           endCenter: CGPoint(x: centerX, y: centerY), endRadius: artSize * 0.72,
                           options: [.drawsAfterEndLocation])

    drawFrostedCircle(cx: centerX, cy: centerY, alpha: 0.22)
    drawMicGlyph(cx: centerX, cy: centerY)

    savePNG(ctx: ctx, filename: "variant1-conic.png")
}

// MARK: - Variant 2: Deep navy squircle + bright rainbow RING + dark glass center + white mic

func makeVariant2() {
    let ctx = makeContext()
    clipToSquircle(ctx: ctx)

    // Deep navy/charcoal gradient background
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bgGrad = CGGradient(
        colorsSpace: colorSpace,
        colors: [
            NSColor(calibratedRed: 0.05, green: 0.08, blue: 0.18, alpha: 1).cgColor,
            NSColor(calibratedRed: 0.02, green: 0.04, blue: 0.10, alpha: 1).cgColor
        ] as CFArray,
        locations: [0.0, 1.0]
    )!
    ctx.drawLinearGradient(bgGrad,
                           start: CGPoint(x: 0, y: canvasSize),
                           end: CGPoint(x: canvasSize, y: 0),
                           options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])

    // Rainbow ring: draw full rainbow circle then mask center with dark disc
    // Use concentric arcs with hue segments
    let ringOuter = circleR + 110.0
    let ringInner = circleR + 28.0
    let numRingSegments = 360

    for i in 0..<numRingSegments {
        let startAngle = CGFloat(i)
        let endAngle = CGFloat(i + 1) + 0.5
        let hue = CGFloat(i) / CGFloat(numRingSegments)
        NSColor(hue: hue, saturation: 1.0, brightness: 1.0, alpha: 1.0).setFill()

        let path = NSBezierPath()
        path.appendArc(withCenter: CGPoint(x: centerX, y: centerY),
                       radius: ringOuter, startAngle: startAngle, endAngle: endAngle, clockwise: false)
        path.appendArc(withCenter: CGPoint(x: centerX, y: centerY),
                       radius: ringInner, startAngle: endAngle, endAngle: startAngle, clockwise: true)
        path.close()
        path.fill()
    }

    // Soft white glow at ring for luminosity
    let ringGlow = CGGradient(
        colorsSpace: colorSpace,
        colors: [
            NSColor(white: 1.0, alpha: 0.0).cgColor,
            NSColor(white: 1.0, alpha: 0.18).cgColor,
            NSColor(white: 1.0, alpha: 0.0).cgColor
        ] as CFArray,
        locations: [0.0, 0.5, 1.0]
    )!
    ctx.saveGState()
    ctx.drawRadialGradient(ringGlow,
                           startCenter: CGPoint(x: centerX, y: centerY), startRadius: ringInner - 4,
                           endCenter: CGPoint(x: centerX, y: centerY), endRadius: ringOuter + 4,
                           options: [])
    ctx.restoreGState()

    // Dark glass center disc — covers inside of ring
    let darkGlassRect = CGRect(x: centerX - ringInner + 1, y: centerY - ringInner + 1,
                               width: (ringInner - 1) * 2, height: (ringInner - 1) * 2)
    let darkGlassPath = NSBezierPath(ovalIn: darkGlassRect)
    NSColor(calibratedRed: 0.03, green: 0.05, blue: 0.14, alpha: 0.92).setFill()
    darkGlassPath.fill()
    // subtle rim on dark glass
    NSColor(white: 1.0, alpha: 0.12).setStroke()
    darkGlassPath.lineWidth = 2.0
    darkGlassPath.stroke()

    drawMicGlyph(cx: centerX, cy: centerY)

    savePNG(ctx: ctx, filename: "variant2-dark-ring.png")
}

// MARK: - Variant 3: Rainbow background + white mic + concentric sound-wave arcs + glass circle

func makeVariant3() {
    let ctx = makeContext()
    clipToSquircle(ctx: ctx)

    // Diagonal rainbow background (same palette as original but different angle — top-right to bottom-left)
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let cgColors = rainbowCGColors() as CFArray
    guard let gradient = CGGradient(colorsSpace: colorSpace, colors: cgColors, locations: rainbowLocations) else { exit(1) }

    ctx.drawLinearGradient(gradient,
                           start: CGPoint(x: canvasSize, y: canvasSize), // top-right
                           end: CGPoint(x: 0, y: 0),                    // bottom-left
                           options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])

    // Dark tint for better contrast with white
    NSColor(white: 0.0, alpha: 0.12).setFill()
    NSBezierPath(rect: CGRect(x: 0, y: 0, width: canvasSize, height: canvasSize)).fill()

    // Frosted glass circle
    drawFrostedCircle(cx: centerX, cy: centerY, alpha: 0.20)

    // Concentric sound-wave arcs radiating from mic center (draw behind mic, inside glass)
    let waveCount = 5
    for i in 1...waveCount {
        let r = circleR * 0.28 + CGFloat(i) * circleR * 0.08
        let alpha: CGFloat = 1.0 - CGFloat(i) * 0.14
        let arcPath = NSBezierPath(ovalIn: CGRect(x: centerX - r, y: centerY - r, width: r*2, height: r*2))
        NSColor(white: 1.0, alpha: alpha * 0.55).setStroke()
        arcPath.lineWidth = 2.5 - CGFloat(i) * 0.3
        arcPath.stroke()
    }

    drawMicGlyph(cx: centerX, cy: centerY)

    savePNG(ctx: ctx, filename: "variant3-waves.png")
}

// MARK: - Variant 4: Radial rainbow (warm center → cool edges) + frosted circle + mic

func makeVariant4() {
    let ctx = makeContext()
    clipToSquircle(ctx: ctx)

    // Soft warm base fill (yellow-orange center)
    NSColor(hue: 0.11, saturation: 0.9, brightness: 1.0, alpha: 1.0).setFill()
    NSBezierPath(rect: CGRect(x: 0, y: 0, width: canvasSize, height: canvasSize)).fill()

    let colorSpace = CGColorSpaceCreateDeviceRGB()

    // Radial rainbow: multiple radial overlapping gradients to simulate color sweep
    // Layer: yellow→green, then blue tinted outer ring, then violet outermost
    let radialStops: [(hue: CGFloat, innerAlpha: CGFloat, outerAlpha: CGFloat, innerR: CGFloat, outerR: CGFloat)] = [
        (0.11, 0.9, 0.0, 0,   artSize * 0.28),  // warm yellow center
        (0.33, 0.7, 0.0, artSize*0.15, artSize*0.45),  // green band
        (0.55, 0.65, 0.0, artSize*0.30, artSize*0.58), // cyan-blue
        (0.67, 0.75, 0.0, artSize*0.42, artSize*0.70), // blue
        (0.80, 0.70, 0.0, artSize*0.52, artSize*0.75), // violet outer
    ]

    for stop in radialStops {
        let innerColor = NSColor(hue: stop.hue, saturation: 1.0, brightness: 1.0, alpha: stop.innerAlpha).cgColor
        let outerColor = NSColor(hue: stop.hue, saturation: 1.0, brightness: 0.9, alpha: stop.outerAlpha).cgColor
        guard let radGrad = CGGradient(colorsSpace: colorSpace,
                                       colors: [innerColor, outerColor] as CFArray,
                                       locations: [0.0, 1.0]) else { continue }
        ctx.drawRadialGradient(radGrad,
                               startCenter: CGPoint(x: centerX, y: centerY), startRadius: stop.innerR,
                               endCenter: CGPoint(x: centerX, y: centerY), endRadius: stop.outerR,
                               options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    }

    // Bright warm glow at center
    let warmGlow = CGGradient(
        colorsSpace: colorSpace,
        colors: [
            NSColor(hue: 0.08, saturation: 0.6, brightness: 1.0, alpha: 0.75).cgColor,
            NSColor(hue: 0.08, saturation: 1.0, brightness: 1.0, alpha: 0.0).cgColor
        ] as CFArray,
        locations: [0.0, 1.0]
    )!
    ctx.drawRadialGradient(warmGlow,
                           startCenter: CGPoint(x: centerX, y: centerY), startRadius: 0,
                           endCenter: CGPoint(x: centerX, y: centerY), endRadius: artSize * 0.35,
                           options: [])

    drawFrostedCircle(cx: centerX, cy: centerY, alpha: 0.22)
    drawMicGlyph(cx: centerX, cy: centerY)

    savePNG(ctx: ctx, filename: "variant4-radial.png")
}

// MARK: - Variant 5: Vertical rainbow gradient + glossy glass disc with highlight + white mic

func makeVariant5() {
    let ctx = makeContext()
    clipToSquircle(ctx: ctx)

    // Vertical rainbow gradient (top-to-bottom)
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let cgColors = rainbowCGColors(saturation: 0.92, brightness: 0.97) as CFArray
    guard let gradient = CGGradient(colorsSpace: colorSpace, colors: cgColors, locations: rainbowLocations) else { exit(1) }

    ctx.drawLinearGradient(gradient,
                           start: CGPoint(x: centerX, y: canvasSize),  // top
                           end: CGPoint(x: centerX, y: 0),              // bottom
                           options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])

    // Glossy glass disc — base fill
    let discRect = CGRect(x: centerX - circleR, y: centerY - circleR, width: circleD, height: circleD)
    let discPath = NSBezierPath(ovalIn: discRect)

    // Base semi-transparent white fill
    NSColor(white: 1.0, alpha: 0.18).setFill()
    discPath.fill()

    // Strong top highlight — a crescent of bright white at top of disc
    // Draw a gradient within the circle from bright white top to transparent bottom
    ctx.saveGState()
    discPath.setClip()

    let highlightGrad = CGGradient(
        colorsSpace: colorSpace,
        colors: [
            NSColor(white: 1.0, alpha: 0.75).cgColor,
            NSColor(white: 1.0, alpha: 0.0).cgColor
        ] as CFArray,
        locations: [0.0, 1.0]
    )!
    ctx.drawLinearGradient(highlightGrad,
                           start: CGPoint(x: centerX, y: centerY + circleR),
                           end: CGPoint(x: centerX, y: centerY + circleR * 0.1),
                           options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])

    // Inner shine: a small bright oval near top
    let shineRect = CGRect(
        x: centerX - circleR * 0.42,
        y: centerY + circleR * 0.42,
        width: circleD * 0.84,
        height: circleD * 0.28
    )
    NSColor(white: 1.0, alpha: 0.42).setFill()
    NSBezierPath(ovalIn: shineRect).fill()

    ctx.restoreGState()

    // Disc rim
    NSColor(white: 1.0, alpha: 0.60).setStroke()
    discPath.lineWidth = 3.5
    discPath.stroke()

    // Subtle bottom shadow reflection on disc
    ctx.saveGState()
    discPath.setClip()
    let shadowGrad = CGGradient(
        colorsSpace: colorSpace,
        colors: [
            NSColor(white: 0.0, alpha: 0.0).cgColor,
            NSColor(white: 0.0, alpha: 0.20).cgColor
        ] as CFArray,
        locations: [0.6, 1.0]
    )!
    ctx.drawLinearGradient(shadowGrad,
                           start: CGPoint(x: centerX, y: centerY),
                           end: CGPoint(x: centerX, y: centerY - circleR),
                           options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    ctx.restoreGState()

    drawMicGlyph(cx: centerX, cy: centerY)

    savePNG(ctx: ctx, filename: "variant5-vertical-glass.png")
}

// MARK: - Variant 6: Rainbow background + bold white WAVEFORM glyph (+ small mic accent) in translucent circle

func makeVariant6() {
    let ctx = makeContext()
    clipToSquircle(ctx: ctx)

    // Diagonal rainbow (reverse direction for variety)
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let cgColors = rainbowCGColors(saturation: 0.95, brightness: 0.98) as CFArray
    guard let gradient = CGGradient(colorsSpace: colorSpace, colors: cgColors, locations: rainbowLocations) else { exit(1) }

    ctx.drawLinearGradient(gradient,
                           start: CGPoint(x: 0, y: 0),                 // bottom-left
                           end: CGPoint(x: canvasSize, y: canvasSize), // top-right
                           options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])

    // Slightly darken for contrast
    NSColor(white: 0.0, alpha: 0.08).setFill()
    NSBezierPath(rect: CGRect(x: 0, y: 0, width: canvasSize, height: canvasSize)).fill()

    // Translucent frosted circle (slightly less frosted — more subtle)
    drawFrostedCircle(cx: centerX, cy: centerY, alpha: 0.18)

    // Large waveform glyph as the primary visual (centered, vertically mid-circle)
    let waveSize = circleD * 0.78
    // Draw waveform slightly above center to leave room for small mic below
    let waveY = centerY + circleD * 0.10
    drawWaveformGlyph(cx: centerX, cy: waveY, size: waveSize)

    // Small mic.fill below the waveform
    let smallMicGlyphHeight = circleD * 0.26
    if let baseImage = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: nil) {
        let pointSize = smallMicGlyphHeight * 0.72
        let cfg = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
        if let configured = baseImage.withSymbolConfiguration(cfg) {
            let symSize = configured.size
            let tinted = NSImage(size: symSize)
            tinted.lockFocus()
            NSColor(white: 1.0, alpha: 0.80).setFill()
            NSRect(origin: .zero, size: symSize).fill()
            configured.draw(in: NSRect(origin: .zero, size: symSize),
                            from: .zero,
                            operation: .destinationIn,
                            fraction: 1.0)
            tinted.unlockFocus()
            let micY = centerY - circleD * 0.26
            let glyphRect = NSRect(
                x: centerX - symSize.width / 2,
                y: micY - symSize.height / 2,
                width: symSize.width,
                height: symSize.height
            )
            tinted.draw(in: glyphRect, from: .zero, operation: .sourceOver, fraction: 1.0)
        }
    }

    savePNG(ctx: ctx, filename: "variant6-waveform.png")
}

// MARK: - Run all variants

print("Generating icon variants...")
makeVariant1()
makeVariant2()
makeVariant3()
makeVariant4()
makeVariant5()
makeVariant6()
print("Done. All variants written to \(outputDir)/")
