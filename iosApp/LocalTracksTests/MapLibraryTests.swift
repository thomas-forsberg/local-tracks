import Foundation
import Shared
import Testing
@testable import LocalTracks

@MainActor
final class FakeRegionDownloader: RegionDownloading {
    enum Behaviour { case complete, fail, waitUntilCancelled }

    var behaviour: Behaviour = .complete
    private(set) var started: [Int64] = []
    private let repository: MapRegionRepository
    private let directory: URL

    init(repository: MapRegionRepository, directory: URL) {
        self.repository = repository
        self.directory = directory
    }

    func download(regionId: Int64) async throws {
        started.append(regionId)
        let region = try #require(repository.region(id: regionId))
        FileManager.default.createFile(atPath: directory.appending(path: region.fileName).path(percentEncoded: false), contents: Data([1]))
        switch behaviour {
        case .complete:
            repository.complete(id: regionId, completedAt: .from(.now), tiles: region.spec.tileCount, bytes: 1_000)
        case .fail:
            throw TestError.offline
        case .waitUntilCancelled:
            try await Task.sleep(for: .seconds(60))
        }
    }

    enum TestError: Error { case offline }
}

@MainActor
struct MapLibraryTests {
    private let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    private let library: MapLibrary
    private let downloader: FakeRegionDownloader

    // A grid square in Nordmarka.
    private let spec = RegionSpec.companion.forSelection(
        selection: BoundingBox(west: 10.70, south: 59.98, east: 10.72, north: 59.99),
        maxZoom: RegionSpecKt.DEFAULT_REGION_MAX_ZOOM
    )

    init() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var fake: FakeRegionDownloader?
        let environment = AppEnvironment(
            databaseDirectory: directory,
            stateStore: InMemoryRecordingStateStore(),
            regionDownloader: { repository, mapsDirectory in
                let downloader = FakeRegionDownloader(repository: repository, directory: mapsDirectory)
                fake = downloader
                return downloader
            }
        )
        library = environment.maps
        downloader = try #require(fake)
    }

    @Test func addingAnAreaDownloadsIt() async {
        let region = library.addArea(named: "Nordmarka", spec: spec)

        #expect(await eventually { library.regions.first { $0.id == region.id }?.isComplete == true })
        #expect(library.areas.map(\.name) == ["Nordmarka"])
        #expect(library.downloading.isEmpty)
    }

    @Test func theOverviewIsCreatedOnlyOnce() async {
        library.downloadOverview()
        #expect(await eventually { library.overview?.isComplete == true })

        library.downloadOverview()

        #expect(library.regions.filter { $0.kind == .overview }.count == 1)
        #expect(downloader.started.count == 1)
    }

    @Test func aFailedDownloadCanBeRetried() async {
        downloader.behaviour = .fail
        let region = library.addArea(named: "Nordmarka", spec: spec)
        #expect(await eventually { library.failures[region.id] != nil })

        downloader.behaviour = .complete
        library.start(region)

        #expect(library.failures[region.id] == nil)
        #expect(await eventually { library.regions.first { $0.id == region.id }?.isComplete == true })
    }

    @Test func pausingStopsTheDownloadWithoutAnError() async {
        downloader.behaviour = .waitUntilCancelled
        let region = library.addArea(named: "Nordmarka", spec: spec)
        #expect(library.downloading.contains(region.id))

        library.pause(region)

        #expect(await eventually { library.downloading.isEmpty })
        #expect(library.failures.isEmpty)
    }

    @Test func deletingStopsTheDownloadAndRemovesTheFile() async {
        downloader.behaviour = .waitUntilCancelled
        let region = library.addArea(named: "Nordmarka", spec: spec)
        let file = library.fileURL(for: region)
        #expect(await eventually { FileManager.default.fileExists(atPath: file.path(percentEncoded: false)) })

        await library.delete(region)

        #expect(library.regions.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: file.path(percentEncoded: false)))
    }

    @Test func renamingIgnoresBlankNames() {
        downloader.behaviour = .waitUntilCancelled
        let region = library.addArea(named: "Area 1", spec: spec)

        library.rename(region, to: "  Nordmarka ")
        library.rename(region, to: "   ")

        #expect(library.areas.first?.name == "Nordmarka")
        #expect(library.nextAreaName() == "Area 2")
    }
}
