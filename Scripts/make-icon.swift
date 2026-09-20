import AppKit
import CoreGraphics
import Foundation

// Generates Resources/AppIcon.icns: a rounded rect with a globe glyph.
let sizes: [(Int, Int)] = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)]
let iconset = "Resources/AppIcon.iconset"
try? FileManager.default.removeItem(atPath: iconset)
try! FileManager.default.createDirectory(atPath: iconset, withIntermediateDirectories: true)

for (points, scale) in sizes {
    let px = points * scale
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext

    let rect = CGRect(x: 0, y: 0, width: px, height: px)
    let inset = CGFloat(px) * 0.06
    let rounded = rect.insetBy(dx: inset, dy: inset)

    // background
    ctx.setFillColor(NSColor(calibratedRed: 0.13, green: 0.35, blue: 0.95, alpha: 1).cgColor)
    ctx.addPath(CGPath(roundedRect: rounded, cornerWidth: CGFloat(px) * 0.22, cornerHeight: CGFloat(px) * 0.22, transform: nil))
    ctx.fillPath()

    // globe
    let g = rounded.insetBy(dx: CGFloat(px) * 0.16, dy: CGFloat(px) * 0.16)
    ctx.setStrokeColor(NSColor.white.cgColor)
    ctx.setLineWidth(CGFloat(px) * 0.055)
    ctx.strokeEllipse(in: g)
    ctx.strokeEllipse(in: CGRect(x: g.midX - g.width * 0.22, y: g.minY, width: g.width * 0.44, height: g.height))
    ctx.move(to: CGPoint(x: g.minX, y: g.midY)); ctx.addLine(to: CGPoint(x: g.maxX, y: g.midY)); ctx.strokePath()
    ctx.move(to: CGPoint(x: g.minX + g.width * 0.1, y: g.minY + g.height * 0.28))
    ctx.addLine(to: CGPoint(x: g.maxX - g.width * 0.1, y: g.minY + g.height * 0.28)); ctx.strokePath()
    ctx.move(to: CGPoint(x: g.minX + g.width * 0.1, y: g.minY + g.height * 0.72))
    ctx.addLine(to: CGPoint(x: g.maxX - g.width * 0.1, y: g.minY + g.height * 0.72)); ctx.strokePath()

    NSGraphicsContext.restoreGraphicsState()
    let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@\(scale)x.png"
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(iconset)/\(name)"))
}

let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset, "-o", "Resources/AppIcon.icns"]
try! task.run()
task.waitUntilExit()
print("iconutil exit: \(task.terminationStatus)")
