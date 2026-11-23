import Foundation
import Shared
import Testing
@testable import LocalTracks

@MainActor
struct RoutesTests {
    private let environment: AppEnvironment

    init() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        environment = AppEnvironment(databaseDirectory: directory, stateStore: InMemoryRecordingStateStore(), locationSource: FakeLocationSource(), barometerSource: FakeBarometerSource())
    }

    // A 500 m-radius loop (about 3.1 km), walked from its southern point.
    @discardableResult
    private func walkLoop(daysAgo: Double, minutes: Double) -> ActivitySummary {
        let repository = environment.repository
        let startedAt = Date.now.addingTimeInterval(-daysAgo * 86_400)
        let id = repository.startActivity(sport: .hiking, startedAt: .from(startedAt))
        let points = (0...300).map { index in
            let angle = -Double.pi / 2 + 2 * Double.pi * Double(index) / 300
            return RecordedPoint(segmentIndex: 0, point: TrackPoint(
                latitude: 59.97 + 500 * sin(angle) / 111_195,
                longitude: 10.73 + 500 * cos(angle) / (111_195 * cos(59.97 * .pi / 180)),
                elevationMeters: nil, time: .from(startedAt), horizontalAccuracyMeters: nil,
                speedMetersPerSecond: nil, barometer: nil, stationaryByMotion: nil
            ))
        }
        let totals = ActivityTotals.companion.ofSeconds(
            activeTimeSeconds: minutes * 60, distanceMeters: 3142, pointCount: Int32(points.count),
            elevationGainMeters: 0, movingTimeSeconds: minutes * 60, stepCount: nil
        )
        repository.appendPoints(activityId: id, firstSeq: 0, points: points, totals: totals)
        repository.finishActivity(activityId: id, finishedAt: .from(startedAt.addingTimeInterval(minutes * 60)), totals: totals)
        return repository.activity(id: id)!
    }

    @Test func walkingTheSameLoopTwiceShowsARouteInStats() async {
        walkLoop(daysAgo: 3, minutes: 40)
        walkLoop(daysAgo: 1, minutes: 36)
        let stats = environment.stats
        let observing = Task { await stats.observe() }
        defer { observing.cancel() }

        #expect(await eventually { stats.routes.count == 1 })
        #expect(stats.routes.first?.displayName == "3,14 km loop" || stats.routes.first?.displayName == "3.14 km loop")
    }

    @Test func anActivityOnARouteSaysHowItCompares() async {
        walkLoop(daysAgo: 3, minutes: 40)
        let second = walkLoop(daysAgo: 1, minutes: 36)

        let detail = environment.activities.detail(for: second)
        await detail.loadRoute()

        #expect(detail.route != nil)
        #expect(detail.routeSummaryLine == "2nd time, 2:00 faster than your average.")
    }

    @Test func ordinalsAndDifferences() {
        #expect(RouteFormat.ordinal(1) == "1st")
        #expect(RouteFormat.ordinal(12) == "12th")
        #expect(RouteFormat.ordinal(23) == "23rd")
        #expect(RouteFormat.versusAverage(seconds: 0.4) == "your average time")
        #expect(RouteFormat.versusAverage(seconds: 70) == "1:10 slower than your average")
    }
}
