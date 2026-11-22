import Foundation
import Shared

// Composition root: creates the long-lived objects once and passes them on explicitly (no DI framework).
@MainActor
final class AppEnvironment {
    let repository: ActivityRepository
    let recorder: ActivityRecorder
    let recording: RecordingController
    let activities: ActivitiesViewModel
    let stats: StatsViewModel
    let mapRegions: MapRegionRepository
    let maps: MapLibrary

    init(
        databaseDirectory: URL,
        stateStore: RecordingStateStore,
        locationSource: LocationSource = CoreLocationSource(),
        barometerSource: BarometerSource = CoreMotionBarometerSource(),
        motionSource: MotionSource = CoreMotionActivitySource(),
        pedometerSource: PedometerSource = CoreMotionPedometerSource(),
        // Defaults to a folder next to the database, for tests.
        mapsDirectory: URL? = nil,
        regionDownloader: ((MapRegionRepository, URL) -> RegionDownloading)? = nil
    ) {
        let database = Database_iosKt.createIosDatabase(
            directoryPath: databaseDirectory.path(percentEncoded: false),
            fileName: "local-tracks.db"
        )
        repository = ActivityRepository(database: database)
        recorder = ActivityRecorder(repository: repository, stateStore: stateStore)
        recording = RecordingController(
            recorder: recorder,
            locationSource: locationSource,
            barometerSource: barometerSource,
            motionSource: motionSource,
            pedometerSource: pedometerSource
        )
        activities = ActivitiesViewModel(repository: repository)
        stats = StatsViewModel(repository: repository)
        mapRegions = MapRegionRepository(database: database)
        let mapsDirectory = mapsDirectory ?? databaseDirectory.appending(path: "Maps", directoryHint: .isDirectory)
        maps = MapLibrary(
            repository: mapRegions,
            directory: mapsDirectory,
            downloader: regionDownloader?(mapRegions, mapsDirectory) ?? KartverketRegionDownloader(repository: mapRegions, directory: mapsDirectory)
        )
    }

    static func live() throws -> AppEnvironment {
        #if DEBUG
        if let demo = DemoMode.fromLaunchArguments() {
            return try demo.makeEnvironment()
        }
        #endif
        return AppEnvironment(
            databaseDirectory: try DatabaseDirectory.prepare(in: DatabaseDirectory.applicationSupport()),
            stateStore: UserDefaultsRecordingStateStore(),
            mapsDirectory: try DatabaseDirectory.prepare(in: DatabaseDirectory.library(), named: "Maps")
        )
    }
}
