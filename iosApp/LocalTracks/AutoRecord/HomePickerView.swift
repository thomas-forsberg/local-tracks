import CoreLocation
import MapLibre
import Shared
import SwiftUI

// Choosing home: the map is moved under a fixed house marker, over the downloaded maps if any.
struct HomePickerView: View {
    let autoRecord: AutoRecordController
    @Environment(\.dismiss) private var dismiss
    @Environment(MapLibrary.self) private var library: MapLibrary?
    @State private var center: CLLocationCoordinate2D?
    @State private var moveTo: PickerMapView.Move?
    @State private var isLocating = false
    @State private var locationFailed = false

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                PickerMapView(
                    regions: library?.displayableRegions ?? [],
                    fileURL: { library?.fileURL(for: $0) ?? URL(fileURLWithPath: "/") },
                    initial: autoRecord.settings.home.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) },
                    moveTo: moveTo,
                    onCenterChange: { center = $0 }
                )
                Image(systemName: "house.circle.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(.white, .blue)
                    .shadow(radius: 2)
                    .allowsHitTesting(false)
            }
            .overlay(alignment: .bottomLeading) {
                if !(library?.displayableRegions.isEmpty ?? true) { MapAttribution() }
            }
            VStack(alignment: .leading, spacing: 12) {
                Text("Move the map so the house is over your home. Anywhere within \(Int(AutoRecordStoreKt.HOME_RADIUS_METERS)) m counts as home.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if locationFailed {
                    Text("Couldn't find your location.").font(.footnote).foregroundStyle(.red)
                }
                Button {
                    Task { await locate() }
                } label: {
                    Label(isLocating ? "Finding your location…" : "Use my current location", systemImage: "location")
                }
                .disabled(isLocating)
            }
            .padding()
        }
        .navigationTitle("Home")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    guard let center else { return }
                    autoRecord.setHome(HomeLocation(latitude: center.latitude, longitude: center.longitude))
                    dismiss()
                }
                .disabled(center == nil)
            }
        }
        .task {
            if autoRecord.settings.home == nil { await locate() }
        }
    }

    // The first fix accurate to 50 m, or the best one within 15 seconds.
    private func locate() async {
        isLocating = true
        locationFailed = false
        defer { isLocating = false }
        var best: CLLocation?
        let deadline = Date.now.addingTimeInterval(15)
        do {
            for try await update in CLLocationUpdate.liveUpdates() {
                if let location = update.location, location.horizontalAccuracy >= 0,
                   location.horizontalAccuracy < (best?.horizontalAccuracy ?? .infinity) {
                    best = location
                }
                if let best, best.horizontalAccuracy <= 50 { break }
                if update.authorizationDenied || Date.now > deadline { break }
            }
        } catch {}
        if let best {
            moveTo = PickerMapView.Move(coordinate: best.coordinate)
        } else {
            locationFailed = true
        }
    }
}

struct PickerMapView: UIViewRepresentable {
    let regions: [MapRegion]
    let fileURL: (MapRegion) -> URL
    let initial: CLLocationCoordinate2D?
    let moveTo: Move?
    let onCenterChange: (CLLocationCoordinate2D) -> Void

    struct Move: Equatable {
        let id = UUID()
        let coordinate: CLLocationCoordinate2D

        static func == (a: Move, b: Move) -> Bool { a.id == b.id }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MLNMapView {
        let styleURL = Bundle.main.url(forResource: "route-style", withExtension: "json")!
        let mapView = MLNMapView(frame: .zero, styleURL: styleURL)
        mapView.delegate = context.coordinator
        mapView.logoView.isHidden = true
        mapView.attributionButton.isHidden = true // shown in SwiftUI instead
        mapView.compassView.isHidden = true
        mapView.isRotateEnabled = false
        mapView.isPitchEnabled = false
        if let initial {
            mapView.setCenter(initial, zoomLevel: 15, animated: false)
        } else {
            mapView.setCenter(CLLocationCoordinate2D(latitude: 65, longitude: 15), zoomLevel: 3.5, animated: false)
        }
        return mapView
    }

    func updateUIView(_ mapView: MLNMapView, context: Context) {
        if let moveTo, moveTo != context.coordinator.parent?.moveTo {
            mapView.setCenter(moveTo.coordinate, zoomLevel: max(mapView.zoomLevel, 15), animated: true)
        }
        context.coordinator.parent = self
        if let style = mapView.style {
            OfflineMapLayers.apply(regions, fileURL: fileURL, to: style)
        }
    }

    @MainActor
    final class Coordinator: NSObject, @preconcurrency MLNMapViewDelegate {
        var parent: PickerMapView?

        func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
            guard let parent else { return }
            OfflineMapLayers.apply(parent.regions, fileURL: parent.fileURL, to: style)
            parent.onCenterChange(mapView.centerCoordinate)
        }

        func mapView(_ mapView: MLNMapView, regionDidChangeAnimated animated: Bool) {
            parent?.onCenterChange(mapView.centerCoordinate)
        }
    }
}
