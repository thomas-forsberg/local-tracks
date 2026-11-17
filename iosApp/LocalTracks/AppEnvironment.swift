import Foundation
import Shared

// Composition root: creates the long-lived objects once and passes them on explicitly (no DI framework).
@MainActor
final class AppEnvironment {
    let repository: ActivityRepository
    let recorder: ActivityRecorder

    init(databaseDirectory: URL) {
        let database = Database_iosKt.createIosDatabase(
            directoryPath: databaseDirectory.path(percentEncoded: false),
            fileName: "local-tracks.db"
        )
        repository = ActivityRepository(database: database)
        recorder = ActivityRecorder(repository: repository)
    }

    static func live() throws -> AppEnvironment {
        AppEnvironment(databaseDirectory: try DatabaseDirectory.prepare(in: DatabaseDirectory.applicationSupport()))
    }
}
