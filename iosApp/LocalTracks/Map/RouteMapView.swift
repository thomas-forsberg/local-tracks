import MapLibre
import SwiftUI

// Shows a recorded route on MapLibre without any map tiles: the style is bundled and has no
// sources, so the map makes no network requests. Offline Kartverket/OpenStreetMap tiles come later.
struct RouteMapView: UIViewRepresentable {
    // One polyline per segment, so a pause is never drawn as a straight line.
    let segments: [[CLLocationCoordinate2D]]

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> MLNMapView {
        let styleURL = Bundle.main.url(forResource: "route-style", withExtension: "json")!
        let mapView = MLNMapView(frame: .zero, styleURL: styleURL)
        mapView.delegate = context.coordinator
        mapView.logoView.isHidden = true
        mapView.attributionButton.isHidden = true // no data sources to attribute yet
        mapView.compassView.isHidden = true
        mapView.isRotateEnabled = false
        mapView.isPitchEnabled = false
        context.coordinator.segments = segments
        return mapView
    }

    func updateUIView(_ mapView: MLNMapView, context: Context) {
        context.coordinator.segments = segments
        context.coordinator.colorScheme = context.environment.colorScheme
        context.coordinator.render(on: mapView)
    }

    @MainActor
    final class Coordinator: NSObject {
        var segments: [[CLLocationCoordinate2D]] = []
        var colorScheme: ColorScheme = .light
        private var hasFittedCamera = false

        func render(on mapView: MLNMapView) {
            guard let style = mapView.style else { return } // called again once the style has loaded
            let background = style.layer(withIdentifier: "background") as? MLNBackgroundStyleLayer
            background?.backgroundColor = NSExpression(forConstantValue: colorScheme == .dark ? UIColor(white: 0.12, alpha: 1) : UIColor(red: 0.94, green: 0.93, blue: 0.9, alpha: 1))

            let polylines = segments.filter { $0.count > 1 }.map { coordinates in
                MLNPolylineFeature(coordinates: coordinates, count: UInt(coordinates.count))
            }
            setShape(MLNMultiPolylineFeature(polylines: polylines), sourceId: "route", in: style) { source in
                let casing = MLNLineStyleLayer(identifier: "route-casing", source: source)
                casing.lineColor = NSExpression(forConstantValue: UIColor.white)
                casing.lineWidth = NSExpression(forConstantValue: 7)
                casing.lineCap = NSExpression(forConstantValue: "round")
                casing.lineJoin = NSExpression(forConstantValue: "round")
                let line = MLNLineStyleLayer(identifier: "route-line", source: source)
                line.lineColor = NSExpression(forConstantValue: UIColor.systemBlue)
                line.lineWidth = NSExpression(forConstantValue: 4)
                line.lineCap = NSExpression(forConstantValue: "round")
                line.lineJoin = NSExpression(forConstantValue: "round")
                return [casing, line]
            }

            let all = segments.flatMap { $0 }
            if !hasFittedCamera, !all.isEmpty {
                fitCamera(to: all, on: mapView)
                hasFittedCamera = true
            }

            // When start and end would overlap on screen (typically a round trip), draw a green ring
            // around a smaller red dot instead of two dots covering each other.
            let overlap = if let first = all.first, let last = all.last {
                Self.markersOverlap(mapView.convert(first, toPointTo: mapView), mapView.convert(last, toPointTo: mapView))
            } else {
                false
            }
            setMarker(at: all.first, id: "start", color: .systemGreen, radius: overlap ? 11 : 7, in: style)
            setMarker(at: all.last, id: "end", color: .systemRed, radius: overlap ? 5 : 7, in: style)
        }

        private func setShape(_ shape: MLNShape, sourceId: String, in style: MLNStyle, layers: (MLNSource) -> [MLNStyleLayer]) {
            if let source = style.source(withIdentifier: sourceId) as? MLNShapeSource {
                source.shape = shape
            } else {
                let source = MLNShapeSource(identifier: sourceId, shape: shape)
                style.addSource(source)
                layers(source).forEach(style.addLayer)
            }
        }

        // A marker is 19 pt across (radius 7 plus a 2.5 pt outline).
        nonisolated static func markersOverlap(_ a: CGPoint, _ b: CGPoint, markerDiameter: CGFloat = 19) -> Bool {
            hypot(a.x - b.x, a.y - b.y) < markerDiameter
        }

        private func setMarker(at coordinate: CLLocationCoordinate2D?, id: String, color: UIColor, radius: Double, in style: MLNStyle) {
            let point = MLNPointFeature()
            if let coordinate { point.coordinate = coordinate }
            setShape(coordinate == nil ? MLNShapeCollectionFeature(shapes: []) : point, sourceId: id, in: style) { source in
                let circle = MLNCircleStyleLayer(identifier: "\(id)-marker", source: source)
                circle.circleColor = NSExpression(forConstantValue: color)
                circle.circleRadius = NSExpression(forConstantValue: radius)
                circle.circleStrokeColor = NSExpression(forConstantValue: UIColor.white)
                circle.circleStrokeWidth = NSExpression(forConstantValue: 2.5)
                return [circle]
            }
        }

        private func fitCamera(to coordinates: [CLLocationCoordinate2D], on mapView: MLNMapView) {
            let latitudes = coordinates.map(\.latitude)
            let longitudes = coordinates.map(\.longitude)
            let bounds = MLNCoordinateBounds(
                sw: CLLocationCoordinate2D(latitude: latitudes.min()!, longitude: longitudes.min()!),
                ne: CLLocationCoordinate2D(latitude: latitudes.max()!, longitude: longitudes.max()!)
            )
            mapView.setVisibleCoordinateBounds(bounds, edgePadding: UIEdgeInsets(top: 40, left: 40, bottom: 40, right: 40), animated: false, completionHandler: nil)
        }
    }
}

extension RouteMapView.Coordinator: @preconcurrency MLNMapViewDelegate {
    func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
        render(on: mapView)
    }
}
