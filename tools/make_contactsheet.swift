#!/usr/bin/env swift
// make_contactsheet.swift — composites icon variants into a labeled contact sheet
// Usage: swift /Users/cf/Projects/SimpleDictation/tools/make_contactsheet.swift

import AppKit
import Foundation

let outputDir = "/Users/cf/Projects/SimpleDictation/tools/icon-variants"
let currentIcon = "/Users/cf/Projects/SimpleDictation/icon_1024.png"

struct IconEntry {
    let path: String
    let label: String
}

let icons: [IconEntry] = [
    IconEntry(path: currentIcon,                              label: "current"),
    IconEntry(path: "\(outputDir)/variant1-conic.png",        label: "1-conic"),
    IconEntry(path: "\(outputDir)/variant2-dark-ring.png",    label: "2-dark-ring"),
    IconEntry(path: "\(outputDir)/variant3-waves.png",        label: "3-waves"),
    IconEntry(path: "\(outputDir)/variant4-radial.png",       label: "4-radial"),
    IconEntry(path: "\(outputDir)/variant5-vertical-glass.png", label: "5-vertical-glass"),
    IconEntry(path: "\(outputDir)/variant6-waveform.png",     label: "6-waveform"),
]

let cols = 4
let rows = 2  // 7 icons in 4+3, last cell blank

let thumbSize: CGFloat = 300
let labelHeight: CGFloat = 44
let padding: CGFloat = 20
let cellW = thumbSize
let cellH = thumbSize + labelHeight

let sheetW = CGFloat(cols) * cellW + CGFloat(cols + 1) * padding
let sheetH = CGFloat(rows) * cellH + CGFloat(rows + 1) * padding

let colorSpace = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(
    data: nil,
    width: Int(sheetW),
    height: Int(sheetH),
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    fputs("ERROR: could not create CGContext\n", stderr)
    exit(1)
}

NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)

// Background
NSColor(calibratedRed: 0.10, green: 0.10, blue: 0.11, alpha: 1.0).setFill()
NSBezierPath(rect: CGRect(x: 0, y: 0, width: sheetW, height: sheetH)).fill()

// Title
let titleAttrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.boldSystemFont(ofSize: 22),
    .foregroundColor: NSColor.white,
]
let titleStr = NSAttributedString(string: "SimpleDictation — Icon Variants", attributes: titleAttrs)
// Title at top (AppKit coords: y=0 is bottom of canvas)
// We'll draw top-to-bottom so row 0 is the top row in visual terms
// CGContext y=0 is bottom, so top of sheet = sheetH

for (index, entry) in icons.enumerated() {
    let col = index % cols
    let row = index / cols   // 0 = first row (top)

    // In CGContext: y=0 is bottom. Row 0 visually = top of sheet.
    // Top of cell in CGContext coords:
    let cellTop = sheetH - padding - CGFloat(row) * (cellH + padding) - cellH
    let cellLeft = padding + CGFloat(col) * (cellW + padding)

    // Load image
    guard let img = NSImage(contentsOfFile: entry.path) else {
        fputs("WARNING: could not load \(entry.path)\n", stderr)
        continue
    }

    // Draw thumbnail (scaled to thumbSize x thumbSize)
    let thumbRect = CGRect(x: cellLeft, y: cellTop + labelHeight, width: thumbSize, height: thumbSize)
    // Rounded rect clip for the thumbnail
    ctx.saveGState()
    let thumbClip = NSBezierPath(roundedRect: thumbRect, xRadius: 18, yRadius: 18)
    thumbClip.setClip()
    img.draw(in: thumbRect, from: .zero, operation: .sourceOver, fraction: 1.0)
    ctx.restoreGState()

    // Label below thumbnail
    let labelRect = CGRect(x: cellLeft, y: cellTop, width: thumbSize, height: labelHeight)
    let labelAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 16, weight: .medium),
        .foregroundColor: NSColor(white: 0.85, alpha: 1.0),
    ]
    let labelStr = NSAttributedString(string: entry.label, attributes: labelAttrs)
    let labelSize = labelStr.size()
    let labelX = cellLeft + (thumbSize - labelSize.width) / 2
    let labelY = cellTop + (labelHeight - labelSize.height) / 2
    labelStr.draw(at: CGPoint(x: labelX, y: labelY))
}

// Output
guard let cgImage = ctx.makeImage() else {
    fputs("ERROR: could not get CGImage\n", stderr)
    exit(1)
}
let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
guard let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
    fputs("ERROR: PNG representation failed\n", stderr)
    exit(1)
}
let outPath = "\(outputDir)/CONTACTSHEET.png"
do {
    try pngData.write(to: URL(fileURLWithPath: outPath))
    print("Contact sheet written: \(outPath)")
    print("Sheet size: \(Int(sheetW))x\(Int(sheetH))")
} catch {
    fputs("ERROR writing contact sheet: \(error)\n", stderr)
    exit(1)
}
