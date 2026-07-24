import AppKit

// Renders AppIcon.icns for ClipDisplay: a rounded-rect gradient tile with the
// SF Symbol "doc.on.clipboard" centered in white. Produces a full .iconset and
// converts it via iconutil.

let sizes = [16, 32, 64, 128, 256, 512, 1024]

func render(_ px: Int) -> Data {
    let size = NSSize(width: px, height: px)
    let image = NSImage(size: size)
    image.lockFocus()

    let ctx = NSGraphicsContext.current!.cgContext
    let rect = NSRect(origin: .zero, size: size)

    // Rounded-rect background with a vertical gradient (macOS app-icon corner radius ≈ 22.5%).
    let radius = CGFloat(px) * 0.225
    let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    path.addClip()
    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.28, green: 0.52, blue: 0.96, alpha: 1),
        NSColor(calibratedRed: 0.13, green: 0.30, blue: 0.72, alpha: 1),
    ])!
    gradient.draw(in: rect, angle: -90)

    // Clipboard glyph, centered, scaled to ~55% of the tile.
    let glyphPx = CGFloat(px) * 0.55
    let config = NSImage.SymbolConfiguration(pointSize: glyphPx, weight: .medium)
    if let symbol = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: nil)?
        .withSymbolConfiguration(config) {
        let s = symbol.size
        // Tint the template symbol white in an ISOLATED transparent layer, so the
        // sourceAtop fill only paints where the glyph's own alpha exists.
        let tinted = NSImage(size: s)
        tinted.lockFocus()
        symbol.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 1.0)
        NSColor.white.set()
        NSRect(origin: .zero, size: s).fill(using: .sourceAtop)
        tinted.unlockFocus()

        let origin = NSPoint(x: (CGFloat(px) - s.width) / 2, y: (CGFloat(px) - s.height) / 2)
        tinted.draw(at: origin, from: .zero, operation: .sourceOver, fraction: 1.0)
    }
    _ = ctx

    image.unlockFocus()

    let tiff = image.tiffRepresentation!
    let bmp = NSBitmapImageRep(data: tiff)!
    return bmp.representation(using: .png, properties: [:])!
}

let fm = FileManager.default
let iconset = "ClipDisplay.iconset"
try? fm.removeItem(atPath: iconset)
try! fm.createDirectory(atPath: iconset, withIntermediateDirectories: true)

// Standard iconset naming: base + @2x variants.
let plan: [(name: String, px: Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for entry in plan {
    let data = render(entry.px)
    try! data.write(to: URL(fileURLWithPath: "\(iconset)/\(entry.name).png"))
}
print("wrote \(iconset)")
