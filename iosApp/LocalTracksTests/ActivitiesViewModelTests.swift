import Foundation
import Shared
import Testing
@testable import LocalTracks

@MainActor
struct ActivitiesViewModelTests {
    private let environment: AppEnvironment

    init() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        environment = AppEnvironment(databaseDirectory: directory, stateStore: InMemoryRecordingStateStore(), locationSource: FakeLocationSource(), barometerSource: FakeBarometerSource())
    }

    private func record(_ sport: Sport) {
        environment.recording.start(sport)
        environment.recording.stop()
    }

    @Test func startsEmptyAndListsActivitiesNewestFirstAsTheyFinish() async {
        let viewModel = environment.activities
        let observing = Task { await viewModel.observe() }
        defer { observing.cancel() }
        #expect(await eventually { viewModel.activities?.isEmpty == true })

        record(.running)
        #expect(await eventually { viewModel.activities?.count == 1 })
        try? await Task.sleep(for: .milliseconds(5)) // distinct start times for a stable order
        record(.cycling)

        #expect(await eventually { viewModel.activities?.map(\.sport) == [.cycling, .running] })
    }

    @Test func doesNotListTheActivityBeingRecorded() async {
        let viewModel = environment.activities
        let observing = Task { await viewModel.observe() }
        defer { observing.cancel() }
        #expect(await eventually { viewModel.activities != nil })

        environment.recording.start(.hiking)

        try? await Task.sleep(for: .milliseconds(100))
        #expect(viewModel.activities?.isEmpty == true)
        environment.recording.stop()
        #expect(await eventually { viewModel.activities?.count == 1 })
    }

    @Test func deleteRemovesTheActivityFromTheListAndTheDatabase() async throws {
        let viewModel = environment.activities
        let observing = Task { await viewModel.observe() }
        defer { observing.cancel() }
        record(.hiking)
        let activity = try #require(await firstActivity(viewModel))

        viewModel.delete(activity)

        #expect(await eventually { viewModel.activities?.isEmpty == true })
        #expect(environment.repository.activity(id: activity.id) == nil)
    }

    private func firstActivity(_ viewModel: ActivitiesViewModel) async -> ActivitySummary? {
        _ = await eventually { viewModel.activities?.first != nil }
        return viewModel.activities?.first
    }

    @Test func routePreviewsComeFromTheStoredPoints() async throws {
        let id = environment.repository.startActivity(sport: .hiking, startedAt: .from(.now))
        let points = (0..<10).map { index in
            RecordedPoint(segmentIndex: 0, point: TrackPoint(
                latitude: 59.9 + Double(index) * 0.001, longitude: 10.7, elevationMeters: nil, time: .from(.now),
                horizontalAccuracyMeters: nil, speedMetersPerSecond: nil, barometer: nil, stationaryByMotion: nil
            ))
        }
        environment.repository.appendPoints(activityId: id, firstSeq: 0, points: points, totals: ActivityTotals.companion.ofSeconds(
            activeTimeSeconds: 60, distanceMeters: 1000, pointCount: 10, elevationGainMeters: 0, movingTimeSeconds: 60, stepCount: nil
        ))
        let activity = try #require(environment.repository.activity(id: id))

        let preview = try #require(environment.activities.routePreview(for: activity))

        #expect(preview.segments.count == 1)
        #expect(preview.segments[0].count == 10)
    }
}
