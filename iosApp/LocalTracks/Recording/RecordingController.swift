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
    // Left over from a crash or the app being killed; offered for resuming or saving on launch.
    private(set) var unfinishedActivity: ActivitySummary?

    @ObservationIgnored private let recorder: ActivityRecorder
    @ObservationIgnored private let locationSource: LocationSource
    @ObservationIgnored private let barometerSource: BarometerSource
    @ObservationIgnored private var sensorTasks: [Task<Void, Never>] = []

    init(recorder: ActivityRecorder, locationSource: LocationSource, barometerSource: BarometerSource) {
        self.recorder = recorder
        self.locationSource = locationSource
        self.barometerSource = barometerSource
        state = recorder.state.value
        unfinishedActivity = recorder.unfinishedActivity()
    }

    func start(_ sport: Sport) {
        guard recorder.start(sport: sport) else { return }
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

    func stop() {
        guard recorder.stop() else { return }
        stopSensors()
        locationProblem = nil
        latestBarometerReading = nil
        refreshState()
    }

    func resumeUnfinished() {
        guard recorder.resumeUnfinished(), let sport = recorder.state.value.progressOrNull()?.sport else { return }
        unfinishedActivity = nil
        startSensors(for: sport)
        refreshState()
    }

    func finishUnfinished() {
        recorder.finishUnfinished()
        unfinishedActivity = nil
    }

    func flush() {
        recorder.flush()
    }

    private func startSensors(for sport: Sport) {
        stopSensors()
        let locationEvents = locationSource.events(for: sport)
        let barometerReadings = barometerSource.readings()
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
        ]
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
            }
        case .problem(let problem):
            locationProblem = problem
        }
    }

    private func handle(_ reading: BarometerReading) {
        recorder.onBarometer(reading: reading)
        latestBarometerReading = reading
    }

    // The Kotlin state is a StateFlow; reading its value after every change keeps this synchronous and testable.
    private func refreshState() {
        state = recorder.state.value
    }
}
