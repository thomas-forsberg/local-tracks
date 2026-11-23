import SwiftUI
import UIKit

// The Topo look: colours taken from Kartverket's topographic map in light mode, the darker
// Night trail palette in dark mode. Compiled into the app and the widget extension.
enum Theme {
    // Warm map paper / deep slate.
    static let background = Color(light: 0xF4EFE4, dark: 0x0F1A1C)
    // Cards and tiles.
    static let surface = Color(light: 0xFBF8F2, dark: 0x172629)
    static let border = Color(light: 0xE2D6C2, dark: 0x22363A)
    static let ink = Color(light: 0x1F2A1E, dark: 0xEEF3F1)
    static let inkSecondary = Color(light: 0x6B5B4A, dark: 0x8FA6A3)
    // Trail-marker red-orange / amber: Start, Stop, the route line, the selected tab.
    static let accent = Color(light: 0xC13B1E, dark: 0xF2A541)
    static let onAccent = Color(light: 0xFFF8F2, dark: 0x1A1206)
    // Calmer actions (Pause, Resume) and things that are fine.
    static let forest = Color(light: 0x2F5D3A, dark: 0x7BC47F)
    static let onForest = Color(light: 0xFFF8F2, dark: 0x0F1A1C)
    // Contour brown: climb and elevation.
    static let climb = Color(light: 0x8A5A2B, dark: 0xD9A06B)
    // Faint contour lines drawn as texture.
    static let contour = Color(light: 0xC9B79C, dark: 0x22363A)

    static let hiking = Color(light: 0x3F6B3A, dark: 0x7BC47F)
    static let cycling = Color(light: 0x2E6E8E, dark: 0x6EC3E8)
    static let running = Color(light: 0x9A6416, dark: 0xE0A852)
}

extension Color {
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            UIColor(rgb: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}

extension Font {
    // Numbers in Barlow Condensed (bundled, SIL Open Font License): tall, narrow and easy to read at a
    // glance, like an instrument. Scales with Dynamic Type relative to `style`.
    static func numbers(_ size: CGFloat, weight: NumberWeight = .semibold, relativeTo style: Font.TextStyle = .title) -> Font {
        .custom(weight.fontName, size: size, relativeTo: style).monospacedDigit()
    }

    // Small uppercase labels above numbers.
    static let statLabel = Font.footnote.weight(.medium)

    enum NumberWeight {
        case medium, semibold, bold

        var fontName: String {
            switch self {
            case .medium: "BarlowCondensed-Medium"
            case .semibold: "BarlowCondensed-SemiBold"
            case .bold: "BarlowCondensed-Bold"
            }
        }
    }
}

// Faint contour lines, the app's signature texture. Purely decorative.
struct ContourLines: View {
    var body: some View {
        Canvas { context, size in
            let w = size.width, h = size.height
            for i in 0..<7 {
                let y = h * (0.25 + CGFloat(i) * 0.11)
                var path = Path()
                path.move(to: CGPoint(x: -20, y: y + 40))
                path.addCurve(
                    to: CGPoint(x: w + 20, y: y - 50),
                    control1: CGPoint(x: w * 0.3, y: y - 30 + CGFloat(i % 2) * 20),
                    control2: CGPoint(x: w * 0.6, y: y + 30)
                )
                context.stroke(path, with: .color(Theme.contour), lineWidth: 1.2)
            }
            var hill = Path()
            hill.addEllipse(in: CGRect(x: w * 0.36, y: h * 0.2, width: w * 0.26, height: h * 0.12))
            context.stroke(hill, with: .color(Theme.contour), lineWidth: 1.2)
        }
        .opacity(0.6)
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}
