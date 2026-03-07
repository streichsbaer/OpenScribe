#!/usr/bin/env swift

import AppKit
import Foundation

struct IconSpec {
    let filename: String
    let pixels: Int
}

let specs: [IconSpec] = [
    .init(filename: "icon_16x16.png", pixels: 16),
    .init(filename: "icon_16x16@2x.png", pixels: 32),
    .init(filename: "icon_32x32.png", pixels: 32),
    .init(filename: "icon_32x32@2x.png", pixels: 64),
    .init(filename: "icon_128x128.png", pixels: 128),
    .init(filename: "icon_128x128@2x.png", pixels: 256),
    .init(filename: "icon_256x256.png", pixels: 256),
    .init(filename: "icon_256x256@2x.png", pixels: 512),
    .init(filename: "icon_512x512.png", pixels: 512),
    .init(filename: "icon_512x512@2x.png", pixels: 1024)
]

guard CommandLine.arguments.count >= 2 else {
    fputs("Usage: \(CommandLine.arguments[0]) <iconset-dir> [preview-png]\n", stderr)
    exit(1)
}

let iconsetURL = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let previewURL = CommandLine.arguments.count > 2 ? URL(fileURLWithPath: CommandLine.arguments[2]) : nil
let fileManager = FileManager.default

try? fileManager.removeItem(at: iconsetURL)
try fileManager.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

let backgroundTop = NSColor(calibratedRed: 0.16, green: 0.19, blue: 0.27, alpha: 1)
let backgroundBottom = NSColor(calibratedRed: 0.06, green: 0.09, blue: 0.15, alpha: 1)
let borderColor = NSColor(calibratedRed: 0.98, green: 0.96, blue: 0.92, alpha: 0.12)
let highlightColor = NSColor(calibratedRed: 1.0, green: 0.96, blue: 0.88, alpha: 0.12)
let markColor = NSColor(calibratedRed: 0.96, green: 0.93, blue: 0.87, alpha: 1)
let accentColor = NSColor(calibratedRed: 0.95, green: 0.48, blue: 0.35, alpha: 1)

func drawIcon(in rect: CGRect) {
    let size = min(rect.width, rect.height)
    let inset = size * 0.055
    let iconRect = rect.insetBy(dx: inset, dy: inset)
    let cornerRadius = size * 0.24

    let base = NSBezierPath(roundedRect: iconRect, xRadius: cornerRadius, yRadius: cornerRadius)
    let gradient = NSGradient(colors: [backgroundTop, backgroundBottom])!
    gradient.draw(in: base, angle: -90)

    borderColor.setStroke()
    base.lineWidth = max(2, size * 0.012)
    base.stroke()

    let highlight = NSBezierPath(roundedRect: iconRect.insetBy(dx: size * 0.02, dy: size * 0.02), xRadius: cornerRadius * 0.85, yRadius: cornerRadius * 0.85)
    highlightColor.setStroke()
    highlight.lineWidth = max(1.5, size * 0.006)
    highlight.stroke()

    let markRect = CGRect(
        x: rect.minX + size * 0.205,
        y: rect.minY + size * 0.205,
        width: size * 0.59,
        height: size * 0.59
    )

    let ring = NSBezierPath(ovalIn: markRect)
    markColor.setStroke()
    ring.lineWidth = max(2.5, size * 0.055)
    ring.stroke()

    let barWidth = size * 0.085
    let corner = barWidth * 0.5
    let centerX = rect.midX
    let baseline = rect.minY + size * 0.34
    let heights = [size * 0.18, size * 0.32, size * 0.18]
    let xOffsets = [-size * 0.17, 0, size * 0.17]

    for (index, height) in heights.enumerated() {
        let barRect = CGRect(
            x: centerX + xOffsets[index] - barWidth / 2,
            y: baseline,
            width: barWidth,
            height: height
        )
        let bar = NSBezierPath(roundedRect: barRect, xRadius: corner, yRadius: corner)
        markColor.setFill()
        bar.fill()
    }

    let accentSize = size * 0.12
    let accentRect = CGRect(
        x: rect.maxX - size * 0.26,
        y: rect.maxY - size * 0.34,
        width: accentSize,
        height: accentSize
    )
    let accent = NSBezierPath(ovalIn: accentRect)
    accentColor.setFill()
    accent.fill()
}

func pngData(pixelSize: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelSize,
        pixelsHigh: pixelSize,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    rep.size = NSSize(width: pixelSize, height: pixelSize)

    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    context.imageInterpolation = .high
    NSGraphicsContext.current = context
    NSColor.clear.setFill()
    NSBezierPath(rect: CGRect(x: 0, y: 0, width: pixelSize, height: pixelSize)).fill()
    drawIcon(in: CGRect(x: 0, y: 0, width: pixelSize, height: pixelSize))
    NSGraphicsContext.restoreGraphicsState()

    return rep.representation(using: .png, properties: [:])!
}

for spec in specs {
    let outputURL = iconsetURL.appendingPathComponent(spec.filename)
    try pngData(pixelSize: spec.pixels).write(to: outputURL)
}

if let previewURL {
    try pngData(pixelSize: 1024).write(to: previewURL)
}
