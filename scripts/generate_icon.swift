import AppKit
import Foundation

let args = CommandLine.arguments
guard args.count >= 2 else {
    fputs("Usage: swift generate_icon.swift <output-iconset-dir>\n", stderr)
    exit(1)
}

let iconsetPath = args[1]
let fm = FileManager.default
try? fm.removeItem(atPath: iconsetPath)
try fm.createDirectory(atPath: iconsetPath, withIntermediateDirectories: true)

func renderIcon(pixelSize: Int) -> Data? {
    guard let rep = NSBitmapImageRep(
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
    ) else { return nil }

    NSGraphicsContext.saveGraphicsState()
    guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else {
        NSGraphicsContext.restoreGraphicsState()
        return nil
    }
    NSGraphicsContext.current = ctx
    let cg = ctx.cgContext
    let s = CGFloat(pixelSize)

    // macOS squircle-like rounded background with airy sky-cyan gradient ("air-cc" / Air Clipboard)
    let pad = s * 0.08
    let bgRect = CGRect(x: pad, y: pad, width: s - pad * 2, height: s - pad * 2)
    let bgRadius = bgRect.width * 0.225
    let bgPath = NSBezierPath(roundedRect: bgRect, xRadius: bgRadius, yRadius: bgRadius)

    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.14, green: 0.56, blue: 0.96, alpha: 1.0),
        NSColor(calibratedRed: 0.34, green: 0.82, blue: 0.98, alpha: 1.0)
    ])
    gradient?.draw(in: bgPath, angle: 65)

    // Floating back card (symbolizing weightless air clipboard history)
    cg.saveGState()
    let backRect = CGRect(x: s * 0.30, y: s * 0.21, width: s * 0.46, height: s * 0.54)
    let backPath = NSBezierPath(roundedRect: backRect, xRadius: s * 0.055, yRadius: s * 0.055)
    NSColor(calibratedWhite: 1.0, alpha: 0.32).setFill()
    backPath.fill()
    cg.restoreGState()

    // Front clipboard sheet
    let frontRect = CGRect(x: s * 0.23, y: s * 0.25, width: s * 0.46, height: s * 0.54)
    let frontPath = NSBezierPath(roundedRect: frontRect, xRadius: s * 0.055, yRadius: s * 0.055)
    NSColor(calibratedWhite: 1.0, alpha: 0.96).setFill()
    frontPath.fill()

    // Top clip tab
    let clipRect = CGRect(x: s * 0.36, y: s * 0.74, width: s * 0.20, height: s * 0.075)
    let clipPath = NSBezierPath(roundedRect: clipRect, xRadius: s * 0.035, yRadius: s * 0.035)
    NSColor(calibratedRed: 0.85, green: 0.92, blue: 1.0, alpha: 1.0).setFill()
    clipPath.fill()

    // Text lines inside front sheet
    let lineColors: [NSColor] = [
        NSColor(calibratedRed: 0.12, green: 0.45, blue: 0.92, alpha: 0.90),
        NSColor(calibratedRed: 0.20, green: 0.50, blue: 0.85, alpha: 0.55),
        NSColor(calibratedRed: 0.20, green: 0.50, blue: 0.85, alpha: 0.40)
    ]
    let lineYs: [CGFloat] = [0.58, 0.47, 0.36]
    let lineWidths: [CGFloat] = [0.30, 0.32, 0.22]

    for i in 0..<3 {
        let lr = CGRect(x: s * 0.30, y: s * lineYs[i], width: s * lineWidths[i], height: s * 0.042)
        let lp = NSBezierPath(roundedRect: lr, xRadius: s * 0.02, yRadius: s * 0.02)
        lineColors[i].setFill()
        lp.fill()
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

let specs: [(name: String, pixels: Int)] = [
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

for spec in specs {
    if let data = renderIcon(pixelSize: spec.pixels) {
        let url = URL(fileURLWithPath: iconsetPath).appendingPathComponent(spec.name)
        try data.write(to: url)
    }
}
