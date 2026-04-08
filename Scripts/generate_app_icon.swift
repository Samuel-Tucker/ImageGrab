#!/usr/bin/env swift

import AppKit
import Foundation

let fileManager = FileManager.default
let scriptURL = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
let rootURL = scriptURL.deletingLastPathComponent().deletingLastPathComponent()
let supportURL = rootURL.appendingPathComponent("Support", isDirectory: true)
let iconsetURL = supportURL.appendingPathComponent("AppIcon.iconset", isDirectory: true)
let outputURL = supportURL.appendingPathComponent("AppIcon.icns")

try? fileManager.removeItem(at: iconsetURL)
try? fileManager.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

let iconSizes: [(String, CGFloat)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

func image(for size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()

    let bounds = NSRect(x: 0, y: 0, width: size, height: size)
    let inset = size * 0.08
    let cardRect = bounds.insetBy(dx: inset, dy: inset)
    let cardRadius = size * 0.22

    let shadow = NSShadow()
    shadow.shadowBlurRadius = size * 0.05
    shadow.shadowOffset = NSSize(width: 0, height: -size * 0.015)
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.18)
    shadow.set()

    let cardPath = NSBezierPath(roundedRect: cardRect, xRadius: cardRadius, yRadius: cardRadius)
    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.12, green: 0.15, blue: 0.22, alpha: 1.0),
        NSColor(calibratedRed: 0.19, green: 0.47, blue: 0.84, alpha: 1.0)
    ])!
    gradient.draw(in: cardPath, angle: -55)

    NSGraphicsContext.saveGraphicsState()
    cardPath.addClip()

    let flareRect = NSRect(
        x: size * 0.22,
        y: size * 0.50,
        width: size * 0.75,
        height: size * 0.40
    )
    let flarePath = NSBezierPath(ovalIn: flareRect)
    NSColor.white.withAlphaComponent(0.13).setFill()
    flarePath.fill()
    NSGraphicsContext.restoreGraphicsState()

    let ringLineWidth = max(2, size * 0.08)
    let ringRect = NSRect(
        x: size * 0.24,
        y: size * 0.24,
        width: size * 0.52,
        height: size * 0.52
    )
    let ringPath = NSBezierPath(ovalIn: ringRect)
    ringPath.lineWidth = ringLineWidth
    NSColor.white.withAlphaComponent(0.96).setStroke()
    ringPath.stroke()

    let lensRect = NSRect(
        x: size * 0.38,
        y: size * 0.38,
        width: size * 0.24,
        height: size * 0.24
    )
    let lensPath = NSBezierPath(ovalIn: lensRect)
    NSColor.white.withAlphaComponent(0.96).setFill()
    lensPath.fill()

    let finderLineWidth = max(1.5, size * 0.05)
    let finderLength = size * 0.10
    let finderInset = size * 0.17
    let corners: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
        (finderInset, size - finderInset, finderLength, -finderLength),
        (size - finderInset, size - finderInset, -finderLength, -finderLength),
        (finderInset, finderInset, finderLength, finderLength),
        (size - finderInset, finderInset, -finderLength, finderLength)
    ]

    let finderPath = NSBezierPath()
    finderPath.lineWidth = finderLineWidth
    finderPath.lineCapStyle = .round

    for corner in corners {
        finderPath.move(to: CGPoint(x: corner.0, y: corner.1))
        finderPath.line(to: CGPoint(x: corner.0 + corner.2, y: corner.1))
        finderPath.move(to: CGPoint(x: corner.0, y: corner.1))
        finderPath.line(to: CGPoint(x: corner.0, y: corner.1 + corner.3))
    }

    NSColor.white.withAlphaComponent(0.92).setStroke()
    finderPath.stroke()

    let highlightRect = NSRect(
        x: size * 0.44,
        y: size * 0.49,
        width: size * 0.06,
        height: size * 0.06
    )
    let highlightPath = NSBezierPath(ovalIn: highlightRect)
    NSColor(calibratedWhite: 1.0, alpha: 0.55).setFill()
    highlightPath.fill()

    image.unlockFocus()
    return image
}

for (filename, size) in iconSizes {
    let image = image(for: size)
    guard let tiffData = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiffData),
          let pngData = bitmap.representation(using: .png, properties: [:]) else {
        fputs("Failed to render \(filename)\n", stderr)
        exit(1)
    }

    try pngData.write(to: iconsetURL.appendingPathComponent(filename))
}

let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconsetURL.path, "-o", outputURL.path]

do {
    try task.run()
    task.waitUntilExit()
    guard task.terminationStatus == 0 else {
        fputs("iconutil failed with status \(task.terminationStatus)\n", stderr)
        exit(task.terminationStatus)
    }
} catch {
    fputs("Failed to run iconutil: \(error)\n", stderr)
    exit(1)
}

print("Generated \(outputURL.path)")
