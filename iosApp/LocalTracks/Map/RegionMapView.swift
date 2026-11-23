import MapLibre
import Shared
import SwiftUI

// The Maps tab's map: downloaded regions with their outlines, and the area about to be downloaded.
struct RegionMapView: UIViewRepresentable {
    let regions: [MapRegion]
    let fileURL: (MapRegion) -> URL
    // The rounded area that would be downloaded, outlined while choosing one.
    let selection: BoundingBox?
    // While choosing an area: the part of the map inside this inset, reported whenever the map moves.
    let selectionInset: UIEdgeInsets?
    var onVisibleSelectionChange: (BoundingBox) -> Void = { _ in }
    // Moves the map to show this area; a new id moves it again even to the same area.
    var focus: FocusRequest?

    struct FocusRequest: Equatable {
        let id = UUID()
        let bounds: BoundingBox
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> MLNMapView {
        let styleURL = Bundle.main.url(forResource: "route-style", withExtension: "json")!
        let mapView = MLNMapView(frame: .zero, styleURL: styleURL)
        mapView.delegate = context.coordinator
        mapView.logoView.isHidden = true
        mapView.attributionButton.isHidden = true // shown in SwiftUI instead
        mapView.compassView.isHidden = true
        mapView.showsScale = false
        mapView.isRotateEnabled = false
        mapView.isPitchEnabled = false
        // Norway; zoom 3.5 fits the whole country on a phone.
        mapView.setCenter(CLLocationCoordinate2D(latitude: 65, longitude: 15), zoomLevel: 3.5, animated: false)
        return mapView
    }

    func updateUIView(_ mapView: MLNMapView, context: Context) {
        let startedSelecting = context.coordinator.parent?.selectionInset == nil && selectionInset != nil
        if let focus, focus != context.coordinator.parent?.focus {
            let bounds = MLNCoordinateBounds(
                sw: CLLocationCoordinate2D(latitude: focus.bounds.south, longitude: focus.bounds.west),
                ne: CLLocationCoordinate2D(latitude: focus.bounds.north, longitude: focus.bounds.east)
            )
            mapView.setVisibleCoordinateBounds(bounds, edgePadding: UIEdgeInsets(top: 24, left: 24, bottom: 24, right: 24), animated: true, completionHandler: nil)
        }
        context.coordinator.parent = self
        context.coordinator.render(on: mapView)
        if startedSelecting {
            // After this update: SwiftUI state mustn't change while a view updates.
            Task { @MainActor in context.coordinator.reportSelection(of: mapView) }
        }
    }

    @MainActor
    final class Coordinator: NSObject {
        var parent: RegionMapView?

        func render(on mapView: MLNMapView) {
            guard let parent, let style = mapView.style else { return }
            OfflineMapLayers.apply(parent.regions, fileURL: parent.fileURL, to: style, below: "area-outlines")

            let outlines = parent.regions.filter { $0.kind == .area }.map { Self.outline(of: $0.spec.bounds) }
            setLines(outlines, id: "area-outlines", color: .secondaryLabel, width: 1.5, dashed: true, in: style)
            setLines(parent.selection.map { [Self.outline(of: $0)] } ?? [], id: "selection-outline", color: UIColor(Theme.accent), width: 3, dashed: false, in: style)
        }

        func reportSelection(of mapView: MLNMapView) {
            guard let inset = parent?.selectionInset, mapView.bounds.width > 0 else { return }
            let rect = mapView.bounds.inset(by: inset)
            let bounds = mapView.convert(rect, toCoordinateBoundsFrom: mapView)
            parent?.onVisibleSelectionChange(BoundingBox(west: bounds.sw.longitude, south: bounds.sw.latitude, east: bounds.ne.longitude, north: bounds.ne.latitude))
        }

        private static func outline(of box: BoundingBox) -> MLNPolylineFeature {
            var corners = [
                CLLocationCoordinate2D(latitude: box.north, longitude: box.west),
                CLLocationCoordinate2D(latitude: box.north, longitude: box.east),
                CLLocationCoordinate2D(latitude: box.south, longitude: box.east),
                CLLocationCoordinate2D(latitude: box.south, longitude: box.west),
                CLLocationCoordinate2D(latitude: box.north, longitude: box.west),
            ]
            return MLNPolylineFeature(coordinates: &corners, count: UInt(corners.count))
        }

        private func setLines(_ lines: [MLNPolylineFeature], id: String, color: UIColor, width: Double, dashed: Bool, in style: MLNStyle) {
            let shape = MLNMultiPolylineFeature(polylines: lines)
            if let source = style.source(withIdentifier: id) as? MLNShapeSource {
                source.shape = shape
                return
            }
            let source = MLNShapeSource(identifier: id, shape: shape)
            style.addSource(source)
            let layer = MLNLineStyleLayer(identifier: id, source: source)
            layer.lineColor = NSExpression(forConstantValue: color)
            layer.lineWidth = NSExpression(forConstantValue: width)
            if dashed { layer.lineDashPattern = NSExpression(forConstantValue: [3, 2]) }
            style.addLayer(layer)
        }
    }
}

extension RegionMapView.Coordinator: @preconcurrency MLNMapViewDelegate {
    func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
        render(on: mapView)
    }

    func mapView(_ mapView: MLNMapView, regionDidChangeAnimated animated: Bool) {
        reportSelection(of: mapView)
    }
}
