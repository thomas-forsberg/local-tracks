import MapLibre
import Shared

// Shows downloaded map regions as raster layers. Each region is its own MBTiles file, read by MapLibre
// through an mbtiles:// URL; the style never references anything on the network.
@MainActor
enum OfflineMapLayers {
    static let attribution = "© Kartverket"

    // Makes the style show exactly these regions, below `belowLayerId` if given, with the overview under
    // every area. A region's layer id includes whether it's complete, so a finished download is re-added
    // and shows the tiles that arrived after MapLibre first read the file.
    static func apply(_ regions: [MapRegion], fileURL: (MapRegion) -> URL, to style: MLNStyle, below belowLayerId: String? = nil) {
        let ordered = regions.filter { $0.kind == .overview } + regions.filter { $0.kind != .overview }
        let wanted = ordered.map(layerId(for:))
        for layer in style.layers where layer.identifier.hasPrefix(prefix) && !wanted.contains(layer.identifier) {
            style.removeLayer(layer)
            style.source(withIdentifier: layer.identifier).map(style.removeSource)
        }

        // Added bottom to top, each directly below the anchor, so later regions end up above earlier ones.
        for region in ordered {
            let id = layerId(for: region)
            guard style.layer(withIdentifier: id) == nil else { continue }
            let url = URL(string: "mbtiles://\(fileURL(region).path(percentEncoded: false))")!
            let source = MLNRasterTileSource(identifier: id, configurationURL: url, tileSize: 256)
            style.addSource(source)
            let layer = MLNRasterStyleLayer(identifier: id, source: source)
            if let anchor = belowLayerId.flatMap(style.layer(withIdentifier:)) {
                style.insertLayer(layer, below: anchor)
            } else {
                style.addLayer(layer)
            }
        }
        keepOverviewAtTheBottom(ordered, in: style)
    }

    private static let prefix = "offline-region-"

    private static func layerId(for region: MapRegion) -> String {
        "\(prefix)\(region.id)-\(region.isComplete ? "complete" : "partial")"
    }

    // A re-added overview would otherwise land above areas added earlier, and its blurry low-zoom tiles
    // would cover their detail.
    private static func keepOverviewAtTheBottom(_ ordered: [MapRegion], in style: MLNStyle) {
        guard let overview = ordered.first(where: { $0.kind == .overview }),
              let overviewLayer = style.layer(withIdentifier: layerId(for: overview)),
              let lowest = style.layers.first(where: { $0.identifier.hasPrefix(prefix) }),
              lowest !== overviewLayer
        else { return }
        style.removeLayer(overviewLayer)
        style.insertLayer(overviewLayer, below: lowest)
    }
}
