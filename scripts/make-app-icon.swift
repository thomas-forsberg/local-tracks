// Draws the app icon in its three iOS appearances (light, dark, tinted) as 1024 px PNGs:
//   swift scripts/make-app-icon.swift iosApp/LocalTracks/Assets.xcassets/AppIcon.appiconset
// Contour lines around a summit, with a trail-marker red route climbing to it: the Topo look.
import AppKit
import Foundation

let size = 1024.0

struct Palette {
    let background: CGColor
    let contour: CGColor
    let casing: CGColor
    let route: CGColor
    let start: CGColor
}

func rgb(_ hex: UInt32) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: 1
    )
}

func grey(_ white: CGFloat) -> CGColor { CGColor(gray: white, alpha: 1) }

let palettes: [(String, Palette)] = [
    ("AppIcon-light", Palette(background: rgb(0xF4EFE4), contour: rgb(0xCDBA9A), casing: rgb(0xFBF8F2), route: rgb(0xC13B1E), start: rgb(0x2F5D3A))),
    ("AppIcon-dark", Palette(background: rgb(0x0F1A1C), contour: rgb(0x2E4448), casing: rgb(0x0F1A1C), route: rgb(0xF2A541), start: rgb(0x7BC47F))),
    // iOS tints this one itself: greys on black.
    ("AppIcon-tinted", Palette(background: grey(0), contour: grey(0.32), casing: grey(0), route: grey(1), start: grey(0.75))),
]

// A wobbly closed loop around the summit, like a contour line.
func contour(center: CGPoint, radius: CGFloat, ring: Int) -> CGPath {
    let path = CGMutablePath()
    let steps = 120
    for step in 0...steps {
        let angle = Double(step) / Double(steps) * 2 * .pi
        let wobble = 1 + 0.07 * sin(3 * angle + Double(ring)) + 0.04 * sin(5 * angle - Double(ring) * 0.7)
        let point = CGPoint(
            x: center.x + radius * 1.25 * cos(angle) * wobble,
            y: center.y + radius * sin(angle) * wobble
        )
        step == 0 ? path.move(to: point) : path.addLine(to: point)
    }
    path.closeSubpath()
    return path
}

func draw(_ palette: Palette, into context: CGContext) {
    context.setFillColor(palette.background)
    context.fill(CGRect(x: 0, y: 0, width: size, height: size))

    // CoreGraphics' y goes up: the summit sits upper right.
    let summit = CGPoint(x: 640, y: 660)
    context.setLineWidth(14)
    context.setStrokeColor(palette.contour)
    for ring in 0..<6 {
        context.addPath(contour(center: summit, radius: 70 + CGFloat(ring) * 92, ring: ring))
        context.strokePath()
    }

    let route = CGMutablePath()
    route.move(to: CGPoint(x: 210, y: 190))
    route.addCurve(to: CGPoint(x: 430, y: 420), control1: CGPoint(x: 380, y: 220), control2: CGPoint(x: 300, y: 370))
    route.addCurve(to: CGPoint(x: 640, y: 660), control1: CGPoint(x: 560, y: 470), control2: CGPoint(x: 560, y: 640))
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.addPath(route)
    context.setLineWidth(92)
    context.setStrokeColor(palette.casing)
    context.strokePath()
    context.addPath(route)
    context.setLineWidth(56)
    context.setStrokeColor(palette.route)
    context.strokePath()

    context.setFillColor(palette.casing)
    context.fillEllipse(in: CGRect(x: 210 - 62, y: 190 - 62, width: 124, height: 124))
    context.setFillColor(palette.start)
    context.fillEllipse(in: CGRect(x: 210 - 42, y: 190 - 42, width: 84, height: 84))
}

let output = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
for (name, palette) in palettes {
    let context = CGContext(
        data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    )!
    draw(palette, into: context)
    let png = NSBitmapImageRep(cgImage: context.makeImage()!).representation(using: .png, properties: [:])!
    try png.write(to: output.appending(path: "\(name).png"))
    print("wrote \(name).png")
}
