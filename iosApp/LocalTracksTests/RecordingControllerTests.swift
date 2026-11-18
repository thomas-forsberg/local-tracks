import Foundation
import Shared
import Testing
@testable import LocalTracks

@MainActor
final class FakeLocationSource: LocationSource {
    private(set) var requestedSports: [Sport] = []
    private(set) var isRunning = false
    private var continuation: AsyncStream<LocationEvent>.Continuation?

    func events(for sport: Sport) -> AsyncStream<LocationEvent> {
        requestedSports.append(sport)
        let (stream, continuation) = AsyncStream.makeStream(of: LocationEvent.self)
        self.continuation = continuation
        isRunning = true
        continuation.onTermination = { _ in Task { @MainActor [weak self] in self?.isRunning = false } }
        return stream
    }

    func send(_ event: sending LocationEvent) {
        continuation?.yield(event)
    }
}

@MainActor
final class FakeBarometerSource: BarometerSource {
    private var continuation: AsyncStream<BarometerReading>.Continuation?

    func readings() -> AsyncStream<BarometerReading> {
        let (stream, continuation) = AsyncStream.makeStream(of: BarometerReading.self)
        self.continuation = continuation
        return stream
    }

    func send(_ reading: sending BarometerReading) {
        continuation?.yield(reading)
    }
}

// Sensor events are handled on separate tasks, so tests wait for their effect.
@MainActor
func eventually(timeout: Duration = .seconds(5), _ condition: () -> Bool) async -> Bool {
    let deadline = ContinuousClock.now + timeout
    while !condition() {
        guard ContinuousClock.now < deadline else { return false }
        try? await Task.sleep(for: .milliseconds(5))
    }
    return true
}

@MainActor
struct RecordingControllerTests {
    private let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    private let location = FakeLocationSource()
    private let barometer = FakeBarometerSource()

    init() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func makeEnvironment() -> AppEnvironment {
        AppEnvironment(databaseDirectory: directory, locationSource: location, barometerSource: barometer)
    }

    private func fix(secondsFromNow seconds: Double, latitude: Double = 59.9) -> LocationEvent {
        .fix(LocationFix(
            time: .from(.now.addingTimeInterval(seconds)),
            latitude: latitude,
            longitude: 10.7,
            horizontalAccuracyMeters: 5,
            altitudeMeters: nil,
            speedMetersPerSecond: nil
        ))
    }

    private func pointCount(_ controller: RecordingController) -> Int32 {
        controller.state.progressOrNull()?.pointCount ?? 0
    }

    @Test func recordsFixesFromTheLocationSourceForTheChosenSport() async {
        let controller = makeEnvironment().recording

        controller.start(.running)
        location.send(fix(secondsFromNow: 1, latitude: 59.9))
        location.send(fix(secondsFromNow: 2, latitude: 59.901))

        #expect(location.requestedSports == [.running])
        #expect(await eventually { pointCount(controller) == 2 })
        #expect(controller.state is RecordingStateRecording)
        #expect((controller.state.progressOrNull()?.distanceMeters ?? 0) > 100)
    }

    @Test func showsALocationProblemUntilTheNextFix() async {
        let controller = makeEnvironment().recording
        controller.start(.cycling)

        location.send(.problem(.approximateLocationOnly))
        #expect(await eventually { controller.locationProblem == .approximateLocationOnly })

        location.send(fix(secondsFromNow: 1))
        #expect(await eventually { controller.locationProblem == nil })
    }

    @Test func stopEndsLocationUpdatesAndSavesTheActivity() async throws {
        let environment = makeEnvironment()
        let controller = environment.recording
        controller.start(.hiking)
        let id = try #require(environment.repository.latestUnfinishedActivity()).id
        location.send(fix(secondsFromNow: 1))
        #expect(await eventually { pointCount(controller) == 1 })

        controller.stop()

        #expect(await eventually { !location.isRunning })
        #expect(environment.repository.activity(id: id)?.finishedAt != nil)
        #expect(environment.repository.trackPoints(activityId: id).count == 1)
    }

    @Test func attachesBarometerReadingsToRecordedPoints() async throws {
        let environment = makeEnvironment()
        let controller = environment.recording
        controller.start(.hiking)
        let id = try #require(environment.repository.latestUnfinishedActivity()).id

        barometer.send(BarometerReading(time: .from(.now), relativeAltitudeMeters: 3.5, pressureKilopascals: 98.7))
        // Readings and fixes arrive on separate tasks; only send the fix once the reading is in.
        #expect(await eventually { controller.latestBarometerReading != nil })
        location.send(fix(secondsFromNow: 1))
        #expect(await eventually { pointCount(controller) == 1 })
        controller.stop()

        let point = try #require(environment.repository.trackPoints(activityId: id).first)
        #expect(point.point.barometer?.relativeAltitudeMeters == 3.5)
    }

    @Test func resumingAnUnfinishedActivityRestartsSensorsForItsSport() async {
        makeEnvironment().recording.start(.hiking) // then the app "crashes"

        let controller = makeEnvironment().recording
        #expect(controller.unfinishedActivity?.sport == .hiking)

        controller.resumeUnfinished()

        #expect(controller.unfinishedActivity == nil)
        #expect(controller.state is RecordingStateRecording, "one tap on Resume continues recording")
        #expect(location.requestedSports == [.hiking, .hiking])
    }
}
