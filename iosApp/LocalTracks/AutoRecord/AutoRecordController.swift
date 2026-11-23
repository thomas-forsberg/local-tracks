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
    @ObservationIgnored private let tickInterval: Duration
    @ObservationIgnored private var policy: AutoRecordPolicy
    @ObservationIgnored private var homeTask: Task<Void, Never>?
    @ObservationIgnored private var watchTasks: [Task<Void, Never>] = []

    init(
        store: AutoRecordStore,
        recording: RecordingController,
        homeMonitor: HomeMonitoring,
        motion: MotionActivityHistory,
        pedometer: PedometerHistory,
        keepAwake: KeepAwake,
        permissions: AutoRecordPermissions,
        notifier: AutoRecordNotifier,
        tickInterval: Duration = .seconds(10)
    ) {
        self.store = store
        self.recording = recording
        self.homeMonitor = homeMonitor
        self.motion = motion
        self.pedometer = pedometer
        self.keepAwake = keepAwake
        self.permissions = permissions
        self.notifier = notifier
        self.tickInterval = tickInterval
        settings = store.settings()
        let state = store.state()
        policy = AutoRecordPolicy(initial: state)
        phase = state.phase
        recording.onUserStarted = { [weak self] in self?.apply(self?.policy.manualRecordingStarted()) }
        recording.onStopped = { [weak self] in
            self?.policy.recordingStopped()
            self?.save()
        }
    }

    var isEnabled: Bool { settings.enabled }

    // Call at every launch, including background relaunches for home events: picks up where it left off.
    func resume() {
        guard settings.enabled, let home = settings.home else { return }
        needsAlwaysLocation = !permissions.hasAlwaysLocation
        startWatchingHome(home)
        if policy.state.phase == .watching { startWatchingMotion() }
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
        resume()
    }

    func disable() {
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
        case .arrived: apply(policy.arrivedHome())
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
        case .stopRecording:
            recording.stopAutomatically()
        }
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
                for sample in await motion.history(from: historyStart, to: .now) {
                    apply(policy.motion(sample: sample))
                }
                apply(policy.tick(now: .from(.now)))
                for await sample in live {
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

    private func stopWatchingMotion() {
        watchTasks.forEach { $0.cancel() }
        watchTasks = []
        keepAwake.stop()
    }

    private func startRecording(_ sport: Sport, departedAt: Date?) async {
        var departure: Departure?
        if let departedAt {
            let walked = await pedometer.walked(from: departedAt, to: .now)
            departure = Departure(at: .from(departedAt), distanceMeters: walked?.meters ?? 0, steps: walked.map { KotlinInt(int: Int32($0.steps)) })
        }
        if recording.startAutomatically(sport, departure: departure) {
            notifier.recordingStarted(sport)
        } else {
            // Something was already being recorded by hand.
            policy.recordingStopped()
            save()
        }
    }

    private func save() {
        store.saveState(state: policy.state)
        phase = policy.state.phase
    }
}
