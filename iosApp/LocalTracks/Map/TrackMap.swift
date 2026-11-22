import CoreLocation
import Shared
import SwiftUI

// A route over whatever map regions are downloaded, credited to Kartverket when any are shown.
struct TrackMap: View {
    let segments: [[CLLocationCoordinate2D]]
    var followsLatest = false
    @Environment(MapLibrary.self) private var library: MapLibrary?

    var body: some View {
        let regions = library?.displayableRegions ?? []
        RouteMapView(
            segments: segments,
            regions: regions,
            fileURL: { region in library?.fileURL(for: region) ?? URL(fileURLWithPath: "/") },
            followsLatest: followsLatest
        )
        .overlay(alignment: .bottomLeading) {
            if !regions.isEmpty { MapAttribution() }
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
