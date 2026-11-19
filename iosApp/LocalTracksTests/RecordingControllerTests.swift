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

@MainActor
final class FakeMotionSource: MotionSource {
    private var continuation: AsyncStream<Bool?>.Continuation?

    func stationaryStates() -> AsyncStream<Bool?> {
        let (stream, continuation) = AsyncStream.makeStream(of: Bool?.self)
        self.continuation = continuation
        return stream
    }

    func send(_ stationary: Bool?) {
        continuation?.yield(stationary)
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
    private let motion = FakeMotionSource()
    // Shared by every environment in a test, like UserDefaults across app launches.
    private let stateStore = InMemoryRecordingStateStore()

    init() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func makeEnvironment() -> AppEnvironment {
        AppEnvironment(databaseDirectory: directory, stateStore: stateStore, locationSource: location, barometerSource: barometer, motionSource: motion)
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

    @Test func continuesRecordingAfterABackgroundRelaunch() async {
        let first = makeEnvironment().recording
        first.start(.cycling)
        location.send(fix(secondsFromNow: 1))
        #expect(await eventually { pointCount(first) == 1 })
        first.flush() // the app is then killed by iOS

        let relaunched = makeEnvironment().recording
        relaunched.continueAfterRelaunch()

        #expect(relaunched.state is RecordingStateRecording)
        #expect(relaunched.unfinishedActivity == nil)
        #expect(location.requestedSports == [.cycling, .cycling])
        location.send(fix(secondsFromNow: 5, latitude: 59.91))
        #expect(await eventually { pointCount(relaunched) == 2 })
    }

    @Test func staysPausedAfterABackgroundRelaunchIfItWasPaused() async {
        let first = makeEnvironment().recording
        first.start(.hiking)
        first.pause() // then iOS kills the app

        let relaunched = makeEnvironment().recording
        relaunched.continueAfterRelaunch()

        #expect(relaunched.state is RecordingStatePaused)
        #expect(location.requestedSports == [.hiking, .hiking], "sensors run while paused, as before the kill")
    }

    @Test func backgroundRelaunchDetection() {
        #expect(AppDelegate.isBackgroundRelaunch(hasLocationLaunchKey: true, applicationState: .background))
        #expect(AppDelegate.isBackgroundRelaunch(hasLocationLaunchKey: false, applicationState: .background))
        #expect(AppDelegate.isBackgroundRelaunch(hasLocationLaunchKey: true, applicationState: .inactive))
        #expect(!AppDelegate.isBackgroundRelaunch(hasLocationLaunchKey: false, applicationState: .inactive))
        #expect(!AppDelegate.isBackgroundRelaunch(hasLocationLaunchKey: false, applicationState: .active))
    }

    @Test func motionSaysStationarySoGpsDriftAddsNoDistance() async throws {
        let environment = makeEnvironment()
        let controller = environment.recording
        controller.start(.hiking)
        let id = try #require(environment.repository.latestUnfinishedActivity()).id

        motion.send(true)
        #expect(await eventually { controller.stationaryByMotion == true })
        location.send(fix(secondsFromNow: 1, latitude: 59.9))
        location.send(fix(secondsFromNow: 2, latitude: 59.90005)) // ~6 m of drift
        #expect(await eventually { pointCount(controller) == 2 })
        controller.stop()

        #expect(environment.repository.activity(id: id)?.totals.distanceMeters == 0)
        #expect(environment.repository.trackPoints(activityId: id).allSatisfy { $0.point.stationaryByMotion?.boolValue == true })
    }
}
