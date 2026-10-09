import AppKit
import Foundation

for role in ["Server", "Client"] {
    let directory = "Assets/Screener\(role).iconset"
    try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
    for points in [16, 32, 128, 256, 512] {
        for scale in [1, 2] {
            let pixels = points * scale
            let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4,
                hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: pixels * 4, bitsPerPixel: 32)!
            bitmap.size = NSSize(width: pixels, height: pixels)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
            let p = CGFloat(pixels)
            let background = NSBezierPath(roundedRect: NSRect(x: p * 0.07, y: p * 0.07, width: p * 0.86, height: p * 0.86), xRadius: p * 0.19, yRadius: p * 0.19)
            let teal = role == "Server" ? NSColor(calibratedRed: 0.10, green: 0.57, blue: 0.57, alpha: 1) : NSColor(calibratedRed: 0.06, green: 0.36, blue: 0.63, alpha: 1)
            NSGradient(starting: teal, ending: NSColor(calibratedRed: 0.03, green: 0.15, blue: 0.28, alpha: 1))!.draw(in: background, angle: -65)
            NSColor.white.setStroke()
            if role == "Client" {
                let back = NSBezierPath(roundedRect: NSRect(x: p * 0.30, y: p * 0.42, width: p * 0.47, height: p * 0.30), xRadius: p * 0.025, yRadius: p * 0.025)
                back.lineWidth = max(1, p * 0.023); back.stroke()
            }
            let displayRect = NSRect(x: p * 0.22, y: p * 0.34, width: p * 0.56, height: p * 0.35)
            let display = NSBezierPath(roundedRect: displayRect, xRadius: p * 0.035, yRadius: p * 0.035)
            teal.withAlphaComponent(0.9).setFill(); display.fill()
            NSColor.white.setStroke(); display.lineWidth = max(1, p * 0.027); display.stroke()
            let stand = NSBezierPath(); stand.move(to: NSPoint(x: p * 0.5, y: p * 0.34)); stand.line(to: NSPoint(x: p * 0.5, y: p * 0.25))
            stand.move(to: NSPoint(x: p * 0.38, y: p * 0.25)); stand.line(to: NSPoint(x: p * 0.62, y: p * 0.25)); stand.lineWidth = max(1, p * 0.027); stand.stroke()
            NSGraphicsContext.restoreGraphicsState()
            let suffix = scale == 2 ? "@2x" : ""
            try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(directory)/icon_\(points)x\(points)\(suffix).png"))
        }
    }
}
