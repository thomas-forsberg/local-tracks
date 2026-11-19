import CoreLocation
import Foundation
import Shared
import Testing
@testable import LocalTracks

@MainActor
struct ActivityDetailViewModelTests {
    private let start = Date(timeIntervalSince1970: 1_789_196_400)

    private func point(_ segment: Int32, _ latitude: Double) -> RecordedPoint {
        RecordedPoint(
            segmentIndex: segment,
            point: TrackPoint(latitude: latitude, longitude: 10.7, elevationMeters: nil, time: .from(start), horizontalAccuracyMeters: nil, speedMetersPerSecond: nil, barometer: nil, stationaryByMotion: nil)
        )
    }

    @Test func splitsPointsIntoOneLinePerSegment() {
        let segments = ActivityDetailViewModel.segments(from: [point(0, 1), point(0, 2), point(1, 3), point(1, 4), point(1, 5)])

        #expect(segments.map { $0.map(\.latitude) } == [[1, 2], [3, 4, 5]])
    }

    @Test func noPointsMeansNoSegments() {
        #expect(ActivityDetailViewModel.segments(from: []).isEmpty)
    }

    @Test func loadsTheStoredRouteAndDerivesTimes() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let repository = AppEnvironment(databaseDirectory: directory, stateStore: InMemoryRecordingStateStore(), locationSource: FakeLocationSource(), barometerSource: FakeBarometerSource()).repository
        let id = repository.startActivity(sport: .hiking, startedAt: .from(start))
        let totals = ActivityTotals.companion.ofSeconds(activeTimeSeconds: 600, distanceMeters: 1500, pointCount: 3, elevationGainMeters: 20, movingTimeSeconds: 500)
        repository.appendPoints(activityId: id, firstSeq: 0, points: [point(0, 59.90), point(0, 59.91), point(1, 59.92)], totals: totals)
        repository.finishActivity(activityId: id, finishedAt: .from(start.addingTimeInterval(900)), totals: totals)
        let viewModel = ActivityDetailViewModel(activity: try #require(repository.activity(id: id)), repository: repository)
        #expect(viewModel.segments == nil)

        viewModel.load()

        #expect(viewModel.segments?.map(\.count) == [2, 1])
        #expect(viewModel.analysis?.profile.count == 3)
        #expect(viewModel.elapsedSeconds == 900)
        #expect(viewModel.averageSpeedMetersPerSecond == 3.0, "over moving time")
    }
}
