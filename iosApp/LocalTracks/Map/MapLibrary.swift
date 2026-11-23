import Foundation
import Observation
import Shared

// Takes the region's id rather than the region: Kotlin objects aren't Sendable, and downloads run off the main actor.
protocol RegionDownloading: Sendable {
    // Fills the region's MBTiles file. Throws on failure; cancelling the task stops it, keeping what arrived.
    func download(regionId: Int64) async throws
}

// Downloads from Kartverket through the Kotlin downloader, which does its work on background threads.
final class KartverketRegionDownloader: RegionDownloading, @unchecked Sendable {
    private let downloader: RegionDownloader

    init(repository: MapRegionRepository, directory: URL) {
        downloader = RegionDownloader_iosKt.createIosRegionDownloader(repository: repository, mapsDirectoryPath: directory.path(percentEncoded: false))
    }

    func download(regionId: Int64) async throws {
        try await downloader.download(regionId: regionId)
    }
}

// The downloaded map regions and their downloads, for the Maps tab and every map in the app.
@MainActor
@Observable
final class MapLibrary {
    private(set) var regions: [MapRegion]
    private(set) var downloading: Set<Int64> = []
    // Why the last download of a region stopped, until it's started again.
    private(set) var failures: [Int64: String] = [:]

    let directory: URL
    @ObservationIgnored private let repository: MapRegionRepository
    @ObservationIgnored private let downloader: RegionDownloading
    @ObservationIgnored private var tasks: [Int64: Task<Void, Never>] = [:]

    init(repository: MapRegionRepository, directory: URL, downloader: RegionDownloading) {
        self.repository = repository
        self.directory = directory
        self.downloader = downloader
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        regions = repository.allRegions()
    }

    var overview: MapRegion? { regions.first { $0.kind == .overview } }

    var areas: [MapRegion] { regions.filter { $0.kind == .area } }

    // Regions with at least some tiles, overview first: what maps can show.
    var displayableRegions: [MapRegion] { regions.filter { $0.downloadedTiles > 0 } }

    // Space iOS can make available for the user's own data (it may clear caches to get there).
    func availableBytes() -> Int64? {
        try? directory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage
    }

    func fileURL(for region: MapRegion) -> URL {
        directory.appending(path: region.fileName)
    }

    // Keeps `regions` current while downloads report progress. Run it from a view's .task.
    func observe() async {
        for await latest in repository.regions() {
            regions = latest
        }
    }

    func downloadOverview() {
        let region = overview ?? repository.create(kind: .overview, name: "Norway", spec: RegionSpec.companion.NORWAY_OVERVIEW, createdAt: .from(.now))
        refresh()
        start(region)
    }

    @discardableResult
    func addArea(named name: String, spec: RegionSpec) -> MapRegion {
        let region = repository.create(kind: .area, name: name, spec: spec, createdAt: .from(.now))
        refresh()
        start(region)
        return region
    }

    func nextAreaName() -> String {
        "Area \(areas.count + 1)"
    }

    func start(_ region: MapRegion) {
        guard tasks[region.id] == nil, !region.isComplete else { return }
        failures[region.id] = nil
        downloading.insert(region.id)
        let id = region.id
        tasks[id] = Task {
            do {
                try await downloader.download(regionId: id)
            } catch is CancellationError {
                // Paused by the user; what arrived is kept.
            } catch {
                if !Task.isCancelled {
                    failures[region.id] = "Download stopped. Check the connection and try again."
                }
            }
            tasks[region.id] = nil
            downloading.remove(region.id)
            refresh()
        }
    }

    func pause(_ region: MapRegion) {
        tasks[region.id]?.cancel()
    }

    // Waits for a running download to stop first, so it can't write to the file after it's gone.
    func delete(_ region: MapRegion) async {
        if let task = tasks[region.id] {
            task.cancel()
            await task.value
        }
        repository.delete(id: region.id)
        try? FileManager.default.removeItem(at: fileURL(for: region))
        failures[region.id] = nil
        refresh()
    }

    func rename(_ region: MapRegion, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        repository.rename(id: region.id, name: trimmed)
        refresh()
    }

    private func refresh() {
        regions = repository.allRegions()
    }
}
