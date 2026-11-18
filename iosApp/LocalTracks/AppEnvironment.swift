import Foundation
import Shared

// Composition root: creates the long-lived objects once and passes them on explicitly (no DI framework).
@MainActor
final class AppEnvironment {
    let repository: ActivityRepository
    let recorder: ActivityRecorder
    let recording: RecordingController
    let activities: ActivitiesViewModel

    init(
        databaseDirectory: URL,
        locationSource: LocationSource = CoreLocationSource(),
        barometerSource: BarometerSource = CoreMotionBarometerSource()
    ) {
        let database = Database_iosKt.createIosDatabase(
            directoryPath: databaseDirectory.path(percentEncoded: false),
            fileName: "local-tracks.db"
        )
        repository = ActivityRepository(database: database)
        recorder = ActivityRecorder(repository: repository)
        recording = RecordingController(recorder: recorder, locationSource: locationSource, barometerSource: barometerSource)
        activities = ActivitiesViewModel(repository: repository)
    }

    static func live() throws -> AppEnvironment {
        AppEnvironment(databaseDirectory: try DatabaseDirectory.prepare(in: DatabaseDirectory.applicationSupport()))
    }
}
