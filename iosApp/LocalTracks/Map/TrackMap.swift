import CoreLocation
import Shared
import SwiftUI

// A route over whatever map regions are downloaded, credited to Kartverket when any are shown.
struct TrackMap: View {
    let segments: [[CLLocationCoordinate2D]]
    var leadIn: [CLLocationCoordinate2D]?
    var followsLatest = false
    @Environment(MapLibrary.self) private var library: MapLibrary?
    @State private var isFollowing = true

    var body: some View {
        let regions = library?.displayableRegions ?? []
        RouteMapView(
            segments: segments,
            leadIn: leadIn,
            regions: regions,
            fileURL: { region in library?.fileURL(for: region) ?? URL(fileURLWithPath: "/") },
            followsLatest: followsLatest,
            isFollowing: $isFollowing
        )
        .overlay(alignment: .bottomLeading) {
            if !regions.isEmpty { MapAttribution() }
        }
        .overlay(alignment: .bottomTrailing) {
            if followsLatest && !isFollowing {
                Button("Re-centre", systemImage: "location.fill") { isFollowing = true }
                    .labelStyle(.iconOnly)
                    .font(.title3)
                    .frame(width: 48, height: 48)
                    .foregroundStyle(Theme.accent)
                    .background(Theme.surface, in: .circle)
                    .overlay(Circle().strokeBorder(Theme.border))
                    .padding(10)
            }
        }
    }
}

struct MapAttribution: View {
    var body: some View {
        Text(OfflineMapLayers.attribution)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.regularMaterial, in: .capsule)
            .padding(8)
    }
}
