import CoreLocation
import Observation
import Shared

// Connects the sensors to the Kotlin recorder and exposes recording state to SwiftUI.
@MainActor
@Observable
final class RecordingController {
    private(set) var state: RecordingState
    private(set) var locationProblem: LocationProblem?
    // Nil until the first reading; stays nil on devices without a barometer, such as the simulator.
    private(set) var latestBarometerReading: BarometerReading?
    // From the motion sensors: true standing still, false moving, nil unknown.
    private(set) var stationaryByMotion: Bool?
    // A database write failed (e.g. the phone is full). Recording continues; points are kept until a write succeeds.
    private(set) var isStorageFailing = false
    // The activity in progress as lines, one per segment, for the live map.
    private(set) var liveSegments: [[CLLocationCoordinate2D]] = []
    // Left over from a crash or the app being killed; offered for resuming or saving on launch.
    private(set) var unfinishedActivity: ActivitySummary?
    // What happened to the activity just stopped, shown until the screen goes back to idle.
    private(set) var stopOutcome: StopOutcome?

    // For auto-record: recordings the user started by hand, and every recording that ends.
    @ObservationIgnored var onUserStarted: (() -> Void)?
    @ObservationIgnored var onStopped: (() -> Void)?
    // Every recorded GPS point, for auto-record's arrival at home.
    @ObservationIgnored var onPointRecorded: ((LocationFix) -> Void)?
    // Every change to the recording, e.g. for the lock-screen card.
    @ObservationIgnored var onStateChange: (() -> Void)?

    @ObservationIgnored private let recorder: ActivityRecorder
    @ObservationIgnored private let locationSource: LocationSource
    @ObservationIgnored private let barometerSource: BarometerSource
    @ObservationIgnored private let motionSource: MotionSource
    @ObservationIgnored private let pedometerSource: PedometerSource
    @ObservationIgnored private var sensorTasks: [Task<Void, Never>] = []
    @ObservationIgnored private let idleAfter: Duration
    @ObservationIgnored private var idleTask: Task<Void, Never>?

    init(
        recorder: ActivityRecorder,
        locationSource: LocationSource,
        barometerSource: BarometerSource,
        motionSource: MotionSource,
        pedometerSource: PedometerSource,
        idleAfter: Duration = .seconds(30)
    ) {
        self.idleAfter = idleAfter
        self.recorder = recorder
        self.locationSource = locationSource
        self.barometerSource = barometerSource
        self.motionSource = motionSource
        self.pedometerSource = pedometerSource
        state = recorder.state.value
        unfinishedActivity = recorder.unfinishedActivity()
    }

    func start(_ sport: Sport) {
        guard recorder.start(sport: sport) else { return }
        began(sport)
        onUserStarted?()
    }

    // Started by auto-record, with the stretch already walked (if any).
    @discardableResult
    func startAutomatically(_ sport: Sport, departure: Departure?) -> Bool {
        guard recorder.startAutomatically(sport: sport, departure: departure) else { return false }
        began(sport)
        return true
    }

    var isAutoStarted: Bool { recorder.isAutoStarted }

    private func began(_ sport: Sport) {
        idleTask?.cancel()
        stopOutcome = nil
        liveSegments = []
        liveSegmentIndex = nil
        startSensors(for: sport)
        refreshState()
    }

    // Sensors keep running while paused: the session ignores fixes, and GPS stays warm for resuming.
    func pause() {
        recorder.pause()
        refreshState()
    }

    func resume() {
        recorder.resume()
        refreshState()
    }

    // For the Pause/Resume button on the lock-screen card.
    func togglePause() {
        if state is RecordingStateRecording {
            pause()
        } else if state is RecordingStatePaused {
            resume()
        }
    }

    // Deletes the recording if it covered no distance.
    func stop() {
        let result = recorder.stop()
        guard result != .notRecording else { return }
        ended(result == .kept ? .saved : .discardedNoDistance)
    }

    // Auto-record's stop on arriving home; deletes the recording if it's too short to be an activity.
    @discardableResult
    func stopAutomatically() -> StopResult {
        let result = recorder.stopAutomatically()
        if result != .notRecording { ended(result == .kept ? .saved : .discardedTooShort) }
        return result
    }

    private func ended(_ outcome: StopOutcome) {
        stopSensors()
        locationProblem = nil
        latestBarometerReading = nil
        stopOutcome = outcome
        refreshState()
        onStopped?()
        idleTask?.cancel()
        idleTask = Task { [weak self, idleAfter] in
            try? await Task.sleep(for: idleAfter)
            guard !Task.isCancelled else { return }
            self?.clearFinished()
        }
    }

    // The finished activity's numbers give way to an empty screen, ready for the next one.
    func clearFinished() {
        idleTask?.cancel()
        idleTask = nil
        stopOutcome = nil
        if recorder.clearFinished() { refreshState() }
    }

    func resumeUnfinished() {
        guard recorder.resumeUnfinished(), let sport = recorder.state.value.progressOrNull()?.sport else { return }
        unfinishedActivity = nil
        reloadLiveSegments()
        startSensors(for: sport)
        refreshState()
        if !recorder.isAutoStarted { onUserStarted?() }
    }

    // Called when iOS relaunched the app in the background mid-recording: carries on without user action.
    func continueAfterRelaunch() {
        guard recorder.continueAfterRelaunch(), let sport = recorder.state.value.progressOrNull()?.sport else { return }
        unfinishedActivity = nil
        reloadLiveSegments()
        startSensors(for: sport)
        refreshState()
    }

    func finishUnfinished() {
        recorder.finishUnfinished()
        unfinishedActivity = nil
    }

    func flush() {
        recorder.flush()
        refreshState()
    }

    private func startSensors(for sport: Sport) {
        stopSensors()
        let locationEvents = locationSource.events(for: sport)
        let barometerReadings = barometerSource.readings()
        let motionStates = motionSource.stationaryStates()
        sensorTasks = [
            Task { [weak self] in
                for await event in locationEvents {
                    self?.handle(event)
                }
            },
            Task { [weak self] in
                for await reading in barometerReadings {
                    self?.handle(reading)
                }
            },
            Task { [weak self] in
                for await stationary in motionStates {
                    self?.handleMotion(stationary)
                }
            },
        ]
        if sport.countsSteps {
            let stepCounts = pedometerSource.stepCounts()
            sensorTasks.append(Task { [weak self] in
                for await steps in stepCounts {
                    self?.handleSteps(steps)
                }
            })
        }
    }

    private func stopSensors() {
        sensorTasks.forEach { $0.cancel() }
        sensorTasks = []
    }

    private func handle(_ event: LocationEvent) {
        switch event {
        case .fix(let fix):
            locationProblem = nil
            if recorder.onLocation(fix: fix) {
                refreshState()
                appendToLiveSegments(fix)
                onPointRecorded?(fix)
            }
        case .problem(let problem):
            locationProblem = problem
        }
    }

    private func handleMotion(_ stationary: Bool?) {
        recorder.onMotion(stationary: stationary.map(KotlinBoolean.init(value:)))
        stationaryByMotion = stationary
    }

    private func handleSteps(_ stepsSinceSensorStart: Int) {
        recorder.onSteps(stepsSinceSensorStart: Int32(stepsSinceSensorStart))
        refreshState()
    }

    private func handle(_ reading: BarometerReading) {
        recorder.onBarometer(reading: reading)
        latestBarometerReading = reading
    }

    @ObservationIgnored private var liveSegmentIndex: Int32?

    private func appendToLiveSegments(_ fix: LocationFix) {
        let coordinate = CLLocationCoordinate2D(latitude: fix.latitude, longitude: fix.longitude)
        let index = state.progressOrNull()?.segmentIndex
        if index == liveSegmentIndex, !liveSegments.isEmpty {
            liveSegments[liveSegments.count - 1].append(coordinate)
        } else {
            liveSegments.append([coordinate])
            liveSegmentIndex = index
        }
    }

    private func reloadLiveSegments() {
        let points = recorder.recordedPoints()
        liveSegments = ActivityDetailViewModel.segments(from: points)
        liveSegmentIndex = points.last?.segmentIndex
    }

    // The Kotlin state is a StateFlow; reading its value after every change keeps this synchronous and testable.
    private func refreshState() {
        state = recorder.state.value
        isStorageFailing = recorder.isStorageFailing
        onStateChange?()
    }
}

enum StopOutcome: Equatable {
    case saved
    // Stopped by hand without having moved.
    case discardedNoDistance
    // Auto-record's trip was too short to be an activity.
    case discardedTooShort
}
