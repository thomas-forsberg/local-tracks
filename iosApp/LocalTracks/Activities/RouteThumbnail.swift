import Shared
import SwiftUI

// A small drawing of the route on a map-coloured patch, for the activity list. Drawn from the points
// on the phone, so it needs no downloaded map.
struct RouteThumbnail: View {
    let preview: RoutePreview?
    let sport: Sport

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12).fill(sport.color.opacity(0.12))
            ContourLines().opacity(0.6)
            if let preview {
                Canvas { context, size in
                    let inset: CGFloat = 10
                    let side = min(size.width, size.height) - inset * 2
                    let origin = CGPoint(x: (size.width - side) / 2, y: (size.height - side) / 2)
                    for segment in preview.segments {
                        var path = Path()
                        for (index, point) in segment.enumerated() {
                            let position = CGPoint(x: origin.x + point.x * side, y: origin.y + point.y * side)
                            index == 0 ? path.move(to: position) : path.addLine(to: position)
                        }
                        context.stroke(path, with: .color(sport.color), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                    }
                }
            } else {
                Image(systemName: sport.systemImage).font(.title).foregroundStyle(sport.color)
            }
        }
        .clipShape(.rect(cornerRadius: 12))
        .accessibilityHidden(true)
    }
}
