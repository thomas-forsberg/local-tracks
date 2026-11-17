import Foundation
import Shared
import Testing
@testable import LocalTracks

// Exercises the real path: Swift → Kotlin → SQLite file on disk.
@MainActor
struct AppEnvironmentTests {
    private let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)

    init() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    @Test func recordedActivitySurvivesReopeningTheDatabase() throws {
        let first = AppEnvironment(databaseDirectory: directory)
        #expect(first.recorder.start(sport: .cycling))
        let id = try #require(first.repository.latestUnfinishedActivity()).id
        #expect(first.recorder.stop())

        let reopened = AppEnvironment(databaseDirectory: directory)

        let activity = try #require(reopened.repository.activity(id: id))
        #expect(activity.sport == .cycling)
        #expect(activity.finishedAt != nil)
        #expect(FileManager.default.fileExists(atPath: directory.appending(path: "local-tracks.db").path(percentEncoded: false)))
    }

    @Test func unfinishedActivityIsFoundAfterRestart() throws {
        let crashed = AppEnvironment(databaseDirectory: directory)
        #expect(crashed.recorder.start(sport: .hiking))

        let restarted = AppEnvironment(databaseDirectory: directory)

        #expect(restarted.recorder.unfinishedActivity()?.sport == .hiking)
    }
}
