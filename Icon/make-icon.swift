// Draws GuitarHUD's app icon and writes Resources/GuitarHUD.icns.
// Run via Icon/make-icon.sh. Nothing else depends on it at build time.
import AppKit

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "./GuitarHUD.iconset"

func hex(_ v: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((v >> 16) & 0xff) / 255,
            green: CGFloat((v >> 8) & 0xff) / 255,
            blue: CGFloat(v & 0xff) / 255, alpha: a)
}

/// The macOS app-icon squircle: content fills ~80% of the canvas.
func squircle(_ s: CGFloat) -> CGPath {
    let m = s * 0.0977
    let side = s - m * 2
    return CGPath(roundedRect: CGRect(x: m, y: m, width: side, height: side),
                  cornerWidth: side * 0.2237, cornerHeight: side * 0.2237,
                  transform: nil)
}

func draw(_ s: CGFloat, _ ctx: CGContext) {
    ctx.translateBy(x: 0, y: s)       // work in top-left coordinates
    ctx.scaleBy(x: 1, y: -1)

    // Body
    let shape = squircle(s)
    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()
    let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                          colors: [hex(0x3A3A45), hex(0x17171B)] as CFArray,
                          locations: [0, 1])!
    ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: 0),
                           end: CGPoint(x: 0, y: s), options: [])
    ctx.restoreGState()

    // Fretboard: 5 strings, 4 fret spaces, sized off the canvas so it scales cleanly.
    let gx = s * 0.30, gw = s * 0.40
    let gy = s * 0.32, gh = s * 0.40
    // Three fret spaces, not four: taller spaces leave room for a dot in the
    // first one without it colliding with the nut.
    let strings = 5, frets = 3
    let dx = gw / CGFloat(strings - 1)
    let dy = gh / CGFloat(frets)

    ctx.setStrokeColor(hex(0xE6E2DA, 0.92))
    ctx.setLineWidth(max(1, s * 0.017))
    ctx.setLineCap(.round)
    for i in 0..<strings {
        let x = gx + dx * CGFloat(i)
        ctx.move(to: CGPoint(x: x, y: gy))
        ctx.addLine(to: CGPoint(x: x, y: gy + gh))
    }
    for j in 1...frets {
        let y = gy + dy * CGFloat(j)
        ctx.move(to: CGPoint(x: gx, y: y))
        ctx.addLine(to: CGPoint(x: gx + gw, y: y))
    }
    ctx.strokePath()

    // Nut
    ctx.setFillColor(hex(0xE6E2DA, 0.95))
    let nutH = max(1, s * 0.030)
    ctx.fill(CGRect(x: gx - s * 0.012, y: gy - nutH * 0.5,
                    width: gw + s * 0.024, height: nutH))

    // Fingering, in the same amber the chord names use in the app.
    ctx.setFillColor(hex(0xFFB454))
    let r = s * 0.046
    for (str, space) in [(1, 2), (2, 1), (3, 2)] {
        let cx = gx + dx * CGFloat(str)
        let cy = gy + dy * (CGFloat(space) - 0.5)
        ctx.fillEllipse(in: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
    }

    // A hairline edge keeps it from melting into a dark Dock.
    ctx.addPath(shape)
    ctx.setStrokeColor(hex(0xFFFFFF, 0.10))
    ctx.setLineWidth(max(1, s * 0.006))
    ctx.strokePath()
}

let sizes: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
for (name, px) in sizes {
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                     isPlanar: false, colorSpaceName: .deviceRGB,
                                     bytesPerRow: 0, bitsPerPixel: 0) else { continue }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    draw(CGFloat(px), NSGraphicsContext.current!.cgContext)
    NSGraphicsContext.restoreGraphicsState()
    if let data = rep.representation(using: .png, properties: [:]) {
        try? data.write(to: URL(fileURLWithPath: "\(out)/\(name).png"))
    }
}
print("wrote \(sizes.count) sizes to \(out)")
