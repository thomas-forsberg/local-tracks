#if DEBUG
import Foundation
import UIKit
import Shared

// Debug-only launch modes for UI tests and screenshots. They use a fresh temporary database,
// so they never touch real recordings.
//   -demoData       a few example activities
//   -demoDataEmpty  no activities
enum DemoMode {
    case sampleActivities
    case empty

    static func fromLaunchArguments(_ arguments: [String] = ProcessInfo.processInfo.arguments) -> DemoMode? {
        if arguments.contains("-demoData") { return .sampleActivities }
        if arguments.contains("-demoDataEmpty") { return .empty }
        return nil
    }

    @MainActor
    func makeEnvironment() throws -> AppEnvironment {
        let directory = FileManager.default.temporaryDirectory.appending(path: "demo-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let environment = AppEnvironment(
            databaseDirectory: directory,
            stateStore: InMemoryRecordingStateStore(),
            locationSource: DemoLocationSource(),
            barometerSource: DemoBarometerSource(),
            pedometerSource: DemoPedometerSource(),
            regionDownloader: { DemoRegionDownloader(repository: $0, directory: $1) }
        )
        if self == .sampleActivities {
            DemoData.seed(environment.repository)
            environment.maps.downloadOverview()
            // Two grid squares around Sognsvann.
            environment.maps.addArea(
                named: "Nordmarka",
                spec: RegionSpec.companion.forSelection(selection: BoundingBox(west: 10.68, south: 59.96, east: 10.76, north: 60.0), maxZoom: 13)
            )
        }
        return environment
    }
}

enum DemoData {
    private struct Sample {
        let sport: Sport
        let start: String
        let minutes: Double
        let kilometers: Double
        let climb: Double
        let latitude: Double
        let longitude: Double
    }

    // Fixed dates and places, so screenshots look the same on every run.
    private static let samples = [
        Sample(sport: .hiking, start: "2026-11-16T09:12:00Z", minutes: 92, kilometers: 5.4, climb: 312, latitude: 59.9765, longitude: 10.7290),
        Sample(sport: .cycling, start: "2026-11-17T14:30:00Z", minutes: 66, kilometers: 23.8, climb: 186, latitude: 59.9139, longitude: 10.7522),
        Sample(sport: .running, start: "2026-11-18T06:45:00Z", minutes: 44, kilometers: 8.1, climb: 64, latitude: 59.2676, longitude: 10.4076),
    ]

    static func seed(_ repository: ActivityRepository) {
        for sample in samples {
            let startedAt = ISO8601DateFormatter().date(from: sample.start)!
            let id = repository.startActivity(sport: sample.sport, startedAt: .from(startedAt))
            let points = loop(around: sample, startingAt: startedAt)
            let totals = ActivityTotals.companion.ofSeconds(
                activeTimeSeconds: sample.minutes * 60,
                distanceMeters: sample.kilometers * 1000,
                pointCount: Int32(points.count),
                elevationGainMeters: sample.climb,
                movingTimeSeconds: sample.minutes * 60,
                stepCount: sample.sport.countsSteps ? KotlinInt(int: Int32(sample.kilometers * 1400)) : nil
            )
            repository.appendPoints(activityId: id, firstSeq: 0, points: points, totals: totals)
            repository.finishActivity(activityId: id, finishedAt: .from(startedAt.addingTimeInterval(sample.minutes * 60)), totals: totals)
        }
    }

    // A circular route of the sample's length, one point per 30 s.
    private static func loop(around sample: Sample, startingAt start: Date) -> [RecordedPoint] {
        let count = Int(sample.minutes * 2)
        let radiusMeters = sample.kilometers * 1000 / (2 * .pi)
        let metersPerDegreeLatitude = 111_195.0
        let metersPerDegreeLongitude = metersPerDegreeLatitude * cos(sample.latitude * .pi / 180)
        return (0..<count).map { index in
            let angle = 2 * Double.pi * Double(index) / Double(count)
            return RecordedPoint(
                segmentIndex: 0,
                point: TrackPoint(
                    latitude: sample.latitude + radiusMeters * sin(angle) / metersPerDegreeLatitude,
                    longitude: sample.longitude + radiusMeters * cos(angle) / metersPerDegreeLongitude,
                    elevationMeters: KotlinDouble(value: 150 + sample.climb / 2 * sin(angle)),
                    time: .from(start.addingTimeInterval(Double(index) * 30)),
                    horizontalAccuracyMeters: KotlinDouble(value: 5),
                    speedMetersPerSecond: nil,
                    barometer: nil,
                    stationaryByMotion: nil
                )
            )
        }
    }
}
// Pretend GPS for demo mode: a loop around Sognsvann at a speed that suits the sport, one fix per second.
@MainActor
final class DemoLocationSource: LocationSource {
    func events(for sport: Sport) -> AsyncStream<LocationEvent> {
        let speed = switch sport {
        case .cycling: 6.0
        case .running: 3.2
        case .hiking: 1.4
        }
        let lapSeconds = 600.0
        let radiusMeters = speed * lapSeconds / (2 * .pi)
        return AsyncStream { continuation in
            let task = Task { @MainActor in
                var second = 0.0
                while !Task.isCancelled {
                    let angle = 2 * Double.pi * second / lapSeconds
                    continuation.yield(.fix(LocationFix(
                        time: .from(.now),
                        latitude: 59.9765 + radiusMeters * sin(angle) / 111_195,
                        longitude: 10.7290 + radiusMeters * cos(angle) / (111_195 * cos(59.9765 * .pi / 180)),
                        horizontalAccuracyMeters: 5,
                        altitudeMeters: nil,
                        speedMetersPerSecond: KotlinDouble(value: speed)
                    )))
                    second += 1
                    try? await Task.sleep(for: .seconds(1))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

// Pretend barometer for demo mode: a steady climb of 0.4 m per second.
@MainActor
final class DemoBarometerSource: BarometerSource {
    func readings() -> AsyncStream<BarometerReading> {
        AsyncStream { continuation in
            let task = Task { @MainActor in
                var altitude = 0.0
                while !Task.isCancelled {
                    continuation.yield(BarometerReading(time: .from(.now), relativeAltitudeMeters: altitude, pressureKilopascals: 100))
                    altitude += 0.4
                    try? await Task.sleep(for: .seconds(1))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

// Pretend map downloads for demo mode: plain tiles drawn on the phone, shaded by zoom level with a grid,
// so screenshots show the maps working without contacting Kartverket.
@MainActor
final class DemoRegionDownloader: RegionDownloading {
    private let repository: MapRegionRepository
    private let directory: URL
    private var tileImages: [Int32: KotlinByteArray] = [:]

    init(repository: MapRegionRepository, directory: URL) {
        self.repository = repository
        self.directory = directory
    }

    func download(regionId: Int64) async throws {
        guard let region = repository.region(id: regionId) else { return }
        let store = MBTilesStore_iosKt.openIosMBTiles(directoryPath: directory.path(percentEncoded: false), fileName: region.fileName)
        defer { store.close() }
        store.writeMetadata(name: region.name, spec: region.spec, attribution: OfflineMapLayers.attribution)
        var tiles: [TileId: KotlinByteArray] = [:]
        let iterator = region.spec.tiles().iterator()
        while iterator.hasNext() {
            let tile = iterator.next() as! TileId
            tiles[tile] = image(forZoom: tile.zoom)
        }
        store.putAll(tiles: tiles)
        repository.complete(id: region.id, completedAt: .from(.now), tiles: store.tileCount(), bytes: store.totalBytes())
    }

    private func image(forZoom zoom: Int32) -> KotlinByteArray {
        if let cached = tileImages[zoom] { return cached }
        let shade = 0.97 - Double(zoom) * 0.015
        let png = UIGraphicsImageRenderer(size: CGSize(width: 256, height: 256)).pngData { context in
            UIColor(red: shade - 0.06, green: shade, blue: shade - 0.1, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: 256, height: 256))
            UIColor(white: 0.5, alpha: 0.4).setStroke()
            context.stroke(CGRect(x: 0, y: 0, width: 256, height: 256))
        }
        let bytes = KotlinByteArray(size: Int32(png.count))
        for (index, byte) in png.enumerated() {
            bytes.set(index: Int32(index), value: Int8(bitPattern: byte))
        }
        tileImages[zoom] = bytes
        return bytes
    }
}

// Pretend pedometer for demo mode: a walker's 1.8 steps per second.
@MainActor
final class DemoPedometerSource: PedometerSource {
    func stepCounts() -> AsyncStream<Int> {
        AsyncStream { continuation in
            let task = Task { @MainActor in
                var seconds = 0.0
                while !Task.isCancelled {
                    continuation.yield(Int(seconds * 1.8))
                    seconds += 1
                    try? await Task.sleep(for: .seconds(1))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
#endif
