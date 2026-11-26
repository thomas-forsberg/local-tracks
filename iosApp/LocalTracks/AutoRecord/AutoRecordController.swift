import Foundation
import Observation
import Shared

// Carries out the Kotlin AutoRecordPolicy on iOS: feeds it home events, motion and clock ticks, and
// starts and stops recordings as it decides.
@MainActor
@Observable
final class AutoRecordController {
    private(set) var settings: AutoRecordSettings
    private(set) var phase: AutoRecordPhase
    // Auto-record is on but can't work because "Always" location access is missing.
    private(set) var needsAlwaysLocation = false

    @ObservationIgnored private let store: AutoRecordStore
    @ObservationIgnored private let recording: RecordingController
    @ObservationIgnored private let homeMonitor: HomeMonitoring
    @ObservationIgnored private let motion: MotionActivityHistory
    @ObservationIgnored private let pedometer: PedometerHistory
    @ObservationIgnored private let keepAwake: KeepAwake
    @ObservationIgnored private let permissions: AutoRecordPermissions
    @ObservationIgnored private let notifier: AutoRecordNotifier
    @ObservationIgnored private let activities: ActivityRepository
    @ObservationIgnored private let carAudio: CarAudio
    @ObservationIgnored private let tickInterval: Duration
    @ObservationIgnored private let carCheckInterval: Duration
    @ObservationIgnored let log: AutoRecordLog?
    @ObservationIgnored private var policy: AutoRecordPolicy
    @ObservationIgnored private var homeTask: Task<Void, Never>?
    @ObservationIgnored private var watchTasks: [Task<Void, Never>] = []
    @ObservationIgnored private var carCheckTask: Task<Void, Never>?
    // CarPlay was connected at some check during the recording in progress.
    @ObservationIgnored private var carAudioSeen = false

    init(
        store: AutoRecordStore,
        recording: RecordingController,
        homeMonitor: HomeMonitoring,
        motion: MotionActivityHistory,
        pedometer: PedometerHistory,
        keepAwake: KeepAwake,
        permissions: AutoRecordPermissions,
        notifier: AutoRecordNotifier,
        activities: ActivityRepository,
        carAudio: CarAudio,
        log: AutoRecordLog? = nil,
        tickInterval: Duration = .seconds(10),
        carCheckInterval: Duration = .seconds(120)
    ) {
        self.store = store
        self.recording = recording
        self.homeMonitor = homeMonitor
        self.motion = motion
        self.pedometer = pedometer
        self.keepAwake = keepAwake
        self.permissions = permissions
        self.notifier = notifier
        self.activities = activities
        self.carAudio = carAudio
        self.tickInterval = tickInterval
        self.carCheckInterval = carCheckInterval
        self.log = log
        settings = store.settings()
        let state = store.state()
        policy = AutoRecordPolicy(initial: state)
        phase = state.phase
        recording.onUserStarted = { [weak self] in self?.apply(self?.policy.manualRecordingStarted()) }
        recording.onPointRecorded = { [weak self] fix in
            guard let self, let home = settings.home else { return }
            apply(policy.position(distanceFromHomeMeters: home.distanceMetersTo(latitude: fix.latitude, longitude: fix.longitude), at: fix.time))
        }
        recording.onStopped = { [weak self] in
            self?.stopCarCheck()
            self?.policy.recordingStopped()
            self?.save()
        }
        recording.onUserStoppedAutomatic = { [weak self] id in
            Task { await self?.checkStoppedByUser(activityId: id) }
        }
    }

    var isEnabled: Bool { settings.enabled }

    // Call at every launch, including background relaunches for home events: picks up where it left off.
    func resume() {
        guard settings.enabled, let home = settings.home else { return }
        needsAlwaysLocation = !permissions.hasAlwaysLocation
        if needsAlwaysLocation { log?.add("Location access isn't Always") }
        startWatchingHome(home)
        if policy.state.phase == .watching { startWatchingMotion() }
        if policy.state.phase == .arrivingHome { startWatchingArrival() }
        if policy.state.phase == .autoRecording || policy.state.phase == .arrivingHome { startCarCheck() }
    }

    // Asks for the permissions first; stays off if "Always" location access isn't given.
    func enable() async {
        guard await permissions.requestAlwaysLocation() else {
            needsAlwaysLocation = true
            return
        }
        needsAlwaysLocation = false
        await permissions.requestNotifications()
        store.setEnabled(enabled: true)
        settings = store.settings()
        log?.add("Turned on")
        resume()
    }

    func disable() {
        log?.add("Turned off")
        store.setEnabled(enabled: false)
        settings = store.settings()
        stopWatchingMotion()
        homeTask?.cancel()
        homeTask = nil
        Task { await homeMonitor.stop() }
        // Start from home next time it's turned on; a recording in progress continues as a normal one.
        policy = AutoRecordPolicy(initial: AutoRecordState.companion.INITIAL)
        save()
    }

    func setHome(_ home: HomeLocation) {
        store.setHome(home: home)
        settings = store.settings()
        log?.add("Home set")
        // Whatever was going on was relative to the old home.
        policy = AutoRecordPolicy(initial: AutoRecordState.companion.INITIAL)
        save()
        if settings.enabled {
            homeTask?.cancel()
            homeTask = nil
            resume()
        }
    }

    private func startWatchingHome(_ home: HomeLocation) {
        guard homeTask == nil else { return }
        let events = homeMonitor.events(home: home, radius: AutoRecordStoreKt.HOME_RADIUS_METERS)
        homeTask = Task { [weak self] in
            for await event in events {
                self?.handle(event)
            }
        }
    }

    private func handle(_ event: HomeEvent) {
        switch event {
        case .left(let date): apply(policy.leftHome(at: .from(date)))
        case .arrived(let date): apply(policy.arrivedHome(at: .from(date)))
        }
    }

    private func apply(_ decision: AutoRecordDecision?) {
        defer { save() }
        guard let decision else { return }
        switch onEnum(of: decision) {
        case .none:
            break
        case .startWatching:
            startWatchingMotion()
        case .stopWatching:
            stopWatchingMotion()
        case .startRecording(let start):
            stopWatchingMotion()
            Task { await startRecording(start.sport, departedAt: start.departedAt?.date) }
        case .watchArrival:
            startWatchingArrival()
        case .stopRecording:
            stopWatchingMotion()
            Task { await stopAtHome() }
        }
    }

    // Home again: a car ride is deleted; anything else is kept, marked if it may have been one, and
    // made a bike ride if it was one.
    private func stopAtHome() async {
        let id = recording.activityInProgressId
        let judgement = await judgeRecordingInProgress()
        guard recording.activityInProgressId == id else { return }
        if let judgement, judgement.verdict == .car {
            log?.add("Recording stopped and deleted: car ride (\(judgement.reason))")
            recording.discardAutomatically()
            return
        }
        switch recording.stopAutomatically() {
        case .kept:
            log?.add("Recording stopped and kept")
            if let id, let judgement { applyToSaved(judgement, activityId: id) }
        case .discarded: log?.add("Recording stopped and deleted: too short")
        default: break
        }
    }

    // Stopped by hand, the user is in charge: nothing is deleted, only marked or made a bike ride.
    private func checkStoppedByUser(activityId: Int64) async {
        guard let activity = activities.activity(id: activityId) else { return }
        let points = activities.trackPoints(activityId: activityId)
        let judgement = await judge(points, sport: activity.sport, until: activity.finishedAt?.date ?? .now)
        log?.add("Stopped by you: \(judgement.verdict.name) (\(judgement.reason))")
        applyToSaved(judgement, activityId: activityId)
    }

    private func applyToSaved(_ judgement: TripJudgement, activityId: Int64) {
        switch judgement.verdict {
        case .car, .suspectedCar:
            activities.setSuspectedCar(activityId: activityId, suspected: true)
            log?.add("Marked as a possible car ride")
        case .cycling:
            activities.changeSport(activityId: activityId, sport: .cycling)
            log?.add("Changed to a bike ride")
        default:
            break
        }
    }

    // While recording automatically, a car ride is caught early instead of running GPS for the whole drive.
    private func startCarCheck() {
        guard carCheckTask == nil else { return }
        carAudioSeen = false
        carCheckTask = Task { [weak self, carCheckInterval] in
            while !Task.isCancelled {
                try? await Task.sleep(for: carCheckInterval)
                guard !Task.isCancelled else { return }
                await self?.checkForCar()
            }
        }
    }

    private func stopCarCheck() {
        carCheckTask?.cancel()
        carCheckTask = nil
    }

    // Internal for tests, which don't wait for the interval.
    func checkForCar() async {
        guard recording.isAutoStarted, let id = recording.activityInProgressId else { return }
        guard let judgement = await judgeRecordingInProgress(), recording.activityInProgressId == id else { return }
        log?.add("Car check: \(judgement.verdict.name) (\(judgement.reason))")
        guard judgement.verdict == .car else { return }
        log?.add("Recording deleted: car ride")
        recording.discardAutomatically()
    }

    private func judgeRecordingInProgress() async -> TripJudgement? {
        guard let sport = recording.state.progressOrNull()?.sport else { return nil }
        return await judge(recording.recordedPoints(), sport: sport, until: .now)
    }

    private func judge(_ points: [RecordedPoint], sport: Sport, until: Date) async -> TripJudgement {
        if carAudio.isConnected { carAudioSeen = true }
        let start = points.first?.point.time?.date ?? until
        // From well before the start, so the reading in force when the trip began is included.
        let motionSamples = await motion.history(from: start.addingTimeInterval(-15 * 60), to: until)
        return TripCheck.shared.judge(points: points, sport: sport, motion: motionSamples, until: .from(until), carAudio: carAudioSeen)
    }

    // Replays the motion history from shortly before leaving home, then follows live updates, with a
    // regular tick because the classifier only reports changes.
    private func startWatchingMotion() {
        guard watchTasks.isEmpty else { return }
        keepAwake.start()
        let leftAt = policy.state.leftHomeAt?.date ?? .now
        let historyStart = leftAt.addingTimeInterval(-AutoRecordPolicy.companion.MAX_BACKFILL_SECONDS - 60)
        let live = motion.samples()
        watchTasks = [
            Task { [weak self] in
                guard let self else { return }
                let history = await motion.history(from: historyStart, to: .now)
                log?.add("Motion before: " + (history.isEmpty ? "none" : history.map(\.logText).joined(separator: ", ")))
                for sample in history {
                    apply(policy.motion(sample: sample))
                }
                apply(policy.tick(now: .from(.now)))
                for await sample in live {
                    log?.add("Motion: \(sample.logText)")
                    apply(policy.motion(sample: sample))
                }
            },
            Task { [weak self, tickInterval] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: tickInterval)
                    self?.apply(self?.policy.tick(now: .from(.now)))
                }
            },
        ]
    }

    // Back in the home circle while recording: the recording keeps the app running and reports positions
    // (see init); motion and a tick catch standing still and the time limit.
    private func startWatchingArrival() {
        guard watchTasks.isEmpty else { return }
        let live = motion.samples()
        watchTasks = [
            Task { [weak self] in
                for await sample in live {
                    self?.apply(self?.policy.motion(sample: sample))
                    // Samples can arrive late: check against the time now, too.
                    self?.apply(self?.policy.tick(now: .from(.now)))
                }
            },
            Task { [weak self, tickInterval] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: tickInterval)
                    self?.apply(self?.policy.tick(now: .from(.now)))
                }
            },
        ]
    }

    private func stopWatchingMotion() {
        watchTasks.forEach { $0.cancel() }
        watchTasks = []
        keepAwake.stop()
    }

    private func startRecording(_ sport: Sport, departedAt: Date?) async {
        var departure: Departure?
        if let departedAt {
            let walked = await pedometer.walked(from: departedAt, to: .now)
            let home = settings.home
            departure = Departure(
                at: .from(departedAt),
                distanceMeters: walked?.meters ?? 0,
                steps: walked.map { KotlinInt(int: Int32($0.steps)) },
                startLatitude: home.map { KotlinDouble(value: $0.latitude) },
                startLongitude: home.map { KotlinDouble(value: $0.longitude) }
            )
        }
        if recording.startAutomatically(sport, departure: departure) {
            log?.add("Recording started: \(sport.name), \(Int(departure?.distanceMeters ?? 0)) m walked before")
            notifier.recordingStarted(sport)
            startCarCheck()
        } else {
            log?.add("Not started: already recording")
            // Something was already being recorded by hand.
            policy.recordingStopped()
            save()
        }
    }

    private func save() {
        store.saveState(state: policy.state)
        if policy.state.phase != phase { log?.add("\(phase.name) → \(policy.state.phase.name)") }
        phase = policy.state.phase
    }
}

private extension MotionSample {
    var logText: String { "\(kind.name) \(at.date.formatted(date: .omitted, time: .standard))" }
}
