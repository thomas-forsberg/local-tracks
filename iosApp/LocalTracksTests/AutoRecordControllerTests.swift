import Foundation
import Shared
import Testing
@testable import LocalTracks

@MainActor
final class FakeHomeMonitor: HomeMonitoring {
    private(set) var watchedHome: HomeLocation?
    private var continuation: AsyncStream<HomeEvent>.Continuation?

    func events(home: HomeLocation, radius: Double) -> AsyncStream<HomeEvent> {
        watchedHome = home
        let (stream, continuation) = AsyncStream.makeStream(of: HomeEvent.self)
        self.continuation = continuation
        return stream
    }

    func stop() async {
        watchedHome = nil
    }

    func send(_ event: HomeEvent) {
        continuation?.yield(event)
    }
}

@MainActor
final class FakeMotionHistory: MotionActivityHistory {
    var history: [(MotionKind, Date)] = []
    private var continuation: AsyncStream<MotionSample>.Continuation?

    func samples() -> AsyncStream<MotionSample> {
        let (stream, continuation) = AsyncStream.makeStream(of: MotionSample.self)
        self.continuation = continuation
        return stream
    }

    func history(from start: Date, to end: Date) async -> [MotionSample] {
        history.filter { $0.1 >= start && $0.1 <= end }.map { MotionSample(kind: $0.0, at: .from($0.1)) }
    }

    func send(_ kind: MotionKind, at date: Date = .now) {
        continuation?.yield(MotionSample(kind: kind, at: .from(date)))
    }
}

@MainActor
final class FakePedometerHistory: PedometerHistory {
    var walked = WalkedDistance(meters: 160, steps: 210)
    private(set) var queriedFrom: Date?

    func walked(from start: Date, to end: Date) async -> WalkedDistance? {
        queriedFrom = start
        return walked
    }
}

@MainActor
final class FakeKeepAwake: KeepAwake {
    private(set) var isRunning = false
    func start() { isRunning = true }
    func stop() { isRunning = false }
}

@MainActor
final class FakePermissions: AutoRecordPermissions {
    var grantsAlways = true
    private(set) var hasAlwaysLocation = false

    func requestAlwaysLocation() async -> Bool {
        hasAlwaysLocation = grantsAlways
        return hasAlwaysLocation
    }

    func requestNotifications() async {}
}

@MainActor
final class FakeNotifier: AutoRecordNotifier {
    private(set) var started: [Sport] = []
    func recordingStarted(_ sport: Sport) { started.append(sport) }
}

@MainActor
final class FakeCarAudio: CarAudio {
    var isConnected = false
}

@MainActor
struct AutoRecordControllerTests {
    private let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    private let home = FakeHomeMonitor()
    private let motion = FakeMotionHistory()
    private let pedometer = FakePedometerHistory()
    private let keepAwake = FakeKeepAwake()
    private let permissions = FakePermissions()
    private let notifier = FakeNotifier()
    private let carAudio = FakeCarAudio()
    private let stateStore = InMemoryRecordingStateStore()
    private let homeLocation = HomeLocation(latitude: 59.94, longitude: 10.72)

    init() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func makeEnvironment() -> AppEnvironment {
        AppEnvironment(
            databaseDirectory: directory,
            stateStore: stateStore,
            locationSource: FakeLocationSource(),
            barometerSource: FakeBarometerSource(),
            motionSource: FakeMotionSource(),
            pedometerSource: FakePedometerSource(),
            autoRecordSensors: AutoRecordSensors(
                homeMonitor: home,
                motion: motion,
                pedometer: pedometer,
                keepAwake: keepAwake,
                permissions: permissions,
                notifier: notifier,
                carAudio: carAudio
            )
        )
    }

    private func enabledEnvironment() async -> AppEnvironment {
        let environment = makeEnvironment()
        environment.autoRecord.setHome(homeLocation)
        await environment.autoRecord.enable()
        return environment
    }

    @Test func staysOffWithoutAlwaysLocationAccess() async {
        permissions.grantsAlways = false
        let environment = makeEnvironment()
        environment.autoRecord.setHome(homeLocation)

        await environment.autoRecord.enable()

        #expect(!environment.autoRecord.isEnabled)
        #expect(environment.autoRecord.needsAlwaysLocation)
        #expect(home.watchedHome == nil)
    }

    @Test func enablingWatchesHome() async {
        _ = await enabledEnvironment()

        #expect(home.watchedHome == homeLocation)
    }

    @Test func walkingAwayStartsAHikeIncludingTheStretchAlreadyWalked() async throws {
        let environment = await enabledEnvironment()
        let setOff = Date.now.addingTimeInterval(-170)
        motion.history = [(.walking, setOff)]

        home.send(.left(.now.addingTimeInterval(-150)))

        #expect(await eventually { environment.recording.state is RecordingStateRecording })
        let progress = try #require(environment.recording.state.progressOrNull())
        #expect(progress.sport == .hiking)
        #expect(progress.distanceMeters == 160)
        #expect(progress.steps?.intValue == 210)
        #expect(abs(try #require(pedometer.queriedFrom).timeIntervalSince(setOff)) < 1)
        #expect(notifier.started == [.hiking])
        #expect(!keepAwake.isRunning)
        let stored = try #require(environment.repository.latestUnfinishedActivity())
        #expect(stored.autoStarted)
        #expect(stored.leadIn?.distanceMeters == 160)
    }

    @Test func drivingAwayRecordsNothingUntilHome() async {
        let environment = await enabledEnvironment()
        motion.history = [(.walking, .now.addingTimeInterval(-150)), (.automotive, .now.addingTimeInterval(-60))]

        home.send(.left(.now.addingTimeInterval(-140)))

        #expect(await eventually { environment.autoRecord.phase == .waitingForHome })
        #expect(environment.recording.state is RecordingStateIdle)
        #expect(!keepAwake.isRunning)
    }

    @Test func arrivingHomeStopsTheRecordingAndDeletesItIfShort() async {
        let environment = await enabledEnvironment()
        motion.history = [(.walking, .now.addingTimeInterval(-170))]
        home.send(.left(.now.addingTimeInterval(-150)))
        #expect(await eventually { environment.recording.state is RecordingStateRecording })

        home.send(.arrived(.now))
        #expect(await eventually { environment.autoRecord.phase == .arrivingHome })
        #expect(environment.recording.state is RecordingStateRecording, "keeps recording to the door")
        motion.send(.stationary, at: .now.addingTimeInterval(-61))

        #expect(await eventually { environment.recording.state is RecordingStateFinished })
        #expect(environment.autoRecord.phase == .atHome)
        #expect(environment.repository.latestUnfinishedActivity() == nil)
        #expect(environment.repository.activity(id: 1) == nil, "deleted: under 5 minutes")
    }

    @Test func theLogTellsWhatHappened() async {
        let environment = await enabledEnvironment()
        motion.history = [(.walking, .now.addingTimeInterval(-170))]
        home.send(.left(.now.addingTimeInterval(-150)))
        #expect(await eventually { environment.recording.state is RecordingStateRecording })

        let lines = environment.autoRecordLog.lines().map { $0.dropFirst(21) }
        #expect(lines.contains("Turned on"))
        #expect(lines.contains("AT_HOME → WATCHING"))
        #expect(lines.contains("WATCHING → AUTO_RECORDING"))
        #expect(lines.contains("Recording started: HIKING, 160 m walked before"))
    }

    // GPS fixes heading north at the given speed, one a second from now (the recorder ignores older ones).
    private func travel(_ environment: AppEnvironment, metersPerSecond speed: Double, seconds: Int) {
        let start = Date.now
        for second in 0...seconds {
            environment.recorder.onLocation(fix: LocationFix(
                time: .from(start.addingTimeInterval(Double(second))),
                latitude: 59.9 + Double(second) * speed / 111_195,
                longitude: 10.7,
                horizontalAccuracyMeters: 5,
                altitudeMeters: nil,
                speedMetersPerSecond: KotlinDouble(value: speed)
            ))
        }
    }

    private func autoRecordingHike(_ environment: AppEnvironment) async {
        motion.history = [(.walking, .now.addingTimeInterval(-170))]
        home.send(.left(.now.addingTimeInterval(-150)))
        _ = await eventually { environment.recording.state is RecordingStateRecording }
    }

    @Test func aCarRideIsDeletedWhileRecording() async throws {
        let environment = await enabledEnvironment()
        await autoRecordingHike(environment)
        let id = try #require(environment.recording.activityInProgressId)
        travel(environment, metersPerSecond: 16.7, seconds: 240)

        await environment.autoRecord.checkForCar()

        #expect(environment.recording.state is RecordingStateFinished)
        #expect(environment.recording.stopOutcome == .discardedCarRide)
        #expect(environment.repository.activity(id: id) == nil)
        #expect(environment.autoRecord.phase == .waitingForHome)
        #expect(environment.autoRecordLog.lines().contains { $0.hasSuffix("Recording deleted: car ride") })
    }

    @Test func aHikeIsLeftAlone() async {
        let environment = await enabledEnvironment()
        await autoRecordingHike(environment)
        travel(environment, metersPerSecond: 1.4, seconds: 240)

        await environment.autoRecord.checkForCar()

        #expect(environment.recording.state is RecordingStateRecording)
    }

    @Test func stoppedByHandAtBikeSpeedsBecomesABikeRide() async throws {
        let environment = await enabledEnvironment()
        await autoRecordingHike(environment)
        let id = try #require(environment.recording.activityInProgressId)
        travel(environment, metersPerSecond: 7, seconds: 240)

        environment.recording.stop()

        #expect(await eventually { environment.repository.activity(id: id)?.sport == .cycling })
        #expect(environment.repository.activity(id: id)?.suspectedCar == false)
    }

    @Test func aCarRideStoppedByHandIsOnlyMarked() async throws {
        let environment = await enabledEnvironment()
        await autoRecordingHike(environment)
        let id = try #require(environment.recording.activityInProgressId)
        travel(environment, metersPerSecond: 8, seconds: 240)
        carAudio.isConnected = true

        environment.recording.stop()

        #expect(await eventually { environment.repository.activity(id: id)?.suspectedCar == true })
        #expect(environment.repository.activity(id: id)?.sport == .hiking)
    }

    @Test func startingByHandWhileWatchingStopsWatching() async {
        let environment = await enabledEnvironment()
        home.send(.left(.now))
        #expect(await eventually { keepAwake.isRunning })

        environment.recording.start(.cycling)

        #expect(environment.autoRecord.phase == .manualRecording)
        #expect(!keepAwake.isRunning)
        environment.recording.stop()
        #expect(environment.autoRecord.phase == .waitingForHome)
    }

    @Test func theStateSurvivesARelaunch() async {
        let environment = await enabledEnvironment()
        motion.history = [(.automotive, .now.addingTimeInterval(-30))]
        home.send(.left(.now.addingTimeInterval(-60)))
        #expect(await eventually { environment.autoRecord.phase == .waitingForHome })

        let relaunched = makeEnvironment()
        relaunched.autoRecord.resume()

        #expect(relaunched.autoRecord.phase == .waitingForHome)
        #expect(relaunched.autoRecord.isEnabled)
    }

    @Test func turningOffStopsWatchingHome() async {
        let environment = await enabledEnvironment()

        environment.autoRecord.disable()

        #expect(await eventually { home.watchedHome == nil })
        #expect(!environment.autoRecord.isEnabled)
    }
}
