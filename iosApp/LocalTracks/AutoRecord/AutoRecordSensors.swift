import CoreLocation
import CoreMotion
import Shared

enum HomeEvent: Equatable, Sendable {
    case left(Date)
    case arrived(Date)
}

// Watches the circle around home. iOS keeps watching while the app isn't running, and relaunches it
// in the background for each crossing; that needs "Always" location access and a session holding it.
@MainActor
protocol HomeMonitoring {
    func events(home: HomeLocation, radius: Double) -> AsyncStream<HomeEvent>
    func stop() async
}

@MainActor
final class CoreLocationHomeMonitor: HomeMonitoring {
    private static let monitorName = "home"
    private static let conditionId = "home"
    private let log: AutoRecordLog

    init(log: AutoRecordLog) {
        self.log = log
    }

    // Holds an "Always" location session for as long as the stream runs: without one, iOS stops
    // reporting home events to an app that isn't in use. Call it at launch, before returning from
    // didFinishLaunching, so the session is retaken at once after iOS ended the app.
    func events(home: HomeLocation, radius: Double) -> AsyncStream<HomeEvent> {
        let center = CLLocationCoordinate2D(latitude: home.latitude, longitude: home.longitude)
        let session = CLServiceSession(authorization: .always)
        let log = log
        return AsyncStream { continuation in
            let task = Task { @MainActor in
                defer { session.invalidate() }
                let diagnostics = Task { @MainActor in
                    var last: [String]?
                    do {
                        for try await diagnostic in session.diagnostics {
                            let problems = diagnostic.problems
                            if problems != last { log.add("Location session: \(problems.isEmpty ? "OK" : problems.joined(separator: ", "))") }
                            last = problems
                        }
                    } catch {}
                }
                defer { diagnostics.cancel() }
                // Opening the monitor by name picks up events iOS saved while the app wasn't running.
                let monitor = await CLMonitor(Self.monitorName)
                if let record = await monitor.record(for: Self.conditionId), Self.isSameCircle(record.condition, center: center, radius: radius) {
                    log.add("Home circle already watched, last state \(record.lastEvent.state.name)")
                } else {
                    // Only when missing (first time, or not restored with a backup) or moved: adding
                    // replaces the condition, which may drop an event not yet delivered.
                    await monitor.add(CLMonitor.CircularGeographicCondition(center: center, radius: radius), identifier: Self.conditionId)
                    log.add("Home circle added")
                }
                do {
                    for try await event in await monitor.events {
                        let problems = event.problems
                        log.add("Home event: \(event.state.name) at \(event.date.formatted(date: .omitted, time: .standard))" + (problems.isEmpty ? "" : " (\(problems.joined(separator: ", ")))"))
                        switch event.state {
                        case .satisfied: continuation.yield(.arrived(event.date))
                        case .unsatisfied: continuation.yield(.left(event.date))
                        default: break
                        }
                    }
                } catch {
                    log.add("Home events ended: \(error.localizedDescription)")
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func stop() async {
        let monitor = await CLMonitor(Self.monitorName)
        await monitor.remove(Self.conditionId)
        log.add("Home circle removed")
    }

    private static func isSameCircle(_ condition: Any, center: CLLocationCoordinate2D, radius: Double) -> Bool {
        guard let circle = condition as? CLMonitor.CircularGeographicCondition else { return false }
        return abs(circle.center.latitude - center.latitude) < 1e-6
            && abs(circle.center.longitude - center.longitude) < 1e-6
            && abs(circle.radius - radius) < 0.5
    }
}

private extension CLMonitor.Event {
    // iOS's reasons for holding events back, if any.
    var problems: [String] {
        [
            (authorizationDenied, "location denied"),
            (authorizationDeniedGlobally, "Location Services off"),
            (authorizationRestricted, "location restricted"),
            (insufficientlyInUse, "app not in use"),
            (accuracyLimited, "precise location off"),
            (conditionUnsupported, "condition unsupported"),
            (conditionLimitExceeded, "too many conditions"),
            (persistenceUnavailable, "persistence unavailable"),
            (serviceSessionRequired, "session required"),
            (authorizationRequestInProgress, "asking the user"),
        ].filter(\.0).map(\.1)
    }
}

private extension CLServiceSession.Diagnostic {
    var problems: [String] {
        [
            (authorizationDenied, "location denied"),
            (authorizationDeniedGlobally, "Location Services off"),
            (authorizationRestricted, "location restricted"),
            (insufficientlyInUse, "app not in use"),
            (serviceSessionRequired, "session required"),
            (fullAccuracyDenied, "precise location off"),
            (alwaysAuthorizationDenied, "Always denied"),
            (authorizationRequestInProgress, "asking the user"),
        ].filter(\.0).map(\.1)
    }
}

private extension CLMonitor.Event.State {
    var name: String {
        switch self {
        case .satisfied: "inside"
        case .unsatisfied: "outside"
        case .unknown: "unknown"
        case .unmonitored: "unmonitored"
        @unknown default: "?"
        }
    }
}

// The motion classifier, live and from its history (iOS keeps about a week).
@MainActor
protocol MotionActivityHistory {
    func samples() -> AsyncStream<MotionSample>
    func history(from start: Date, to end: Date) async -> [MotionSample]
}

@MainActor
final class CoreMotionActivityHistory: MotionActivityHistory {
    private var manager: CMMotionActivityManager?

    func samples() -> AsyncStream<MotionSample> {
        stop()
        return AsyncStream { continuation in
            guard CMMotionActivityManager.isActivityAvailable() else {
                continuation.finish()
                return
            }
            let manager = CMMotionActivityManager()
            self.manager = manager
            manager.startActivityUpdates(to: .main) { activity in
                guard let activity else { return }
                continuation.yield(MotionSample(kind: Self.kind(of: activity).motionKind, at: .from(activity.startDate)))
            }
            continuation.onTermination = { _ in Task { @MainActor [weak self] in self?.stop() } }
        }
    }

    func history(from start: Date, to end: Date) async -> [MotionSample] {
        guard CMMotionActivityManager.isActivityAvailable() else { return [] }
        let manager = CMMotionActivityManager()
        // Plain Swift values cross back from the callback; Kotlin objects aren't Sendable.
        let activities: [(ActivityKind, Date)] = await withCheckedContinuation { continuation in
            manager.queryActivityStarting(from: start, to: end, to: .main) { activities, _ in
                continuation.resume(returning: (activities ?? []).map { (Self.kind(of: $0), $0.startDate) })
            }
        }
        return activities.map { MotionSample(kind: $0.0.motionKind, at: .from($0.1)) }
    }

    enum ActivityKind: Sendable {
        case stationary, walking, running, cycling, automotive, unknown

        var motionKind: MotionKind {
            switch self {
            case .stationary: .stationary
            case .walking: .walking
            case .running: .running
            case .cycling: .cycling
            case .automotive: .automotive
            case .unknown: .unknown
            }
        }
    }

    // Driving wins when several are set (e.g. walking to the car as it pulls away); uncertain readings count as unknown.
    nonisolated static func kind(of activity: CMMotionActivity) -> ActivityKind {
        guard activity.confidence != .low else { return .unknown }
        if activity.automotive { return .automotive }
        if activity.cycling { return .cycling }
        if activity.running { return .running }
        if activity.walking { return .walking }
        if activity.stationary { return .stationary }
        return .unknown
    }

    private func stop() {
        manager?.stopActivityUpdates()
        manager = nil
    }
}

struct WalkedDistance: Equatable, Sendable {
    let meters: Double
    let steps: Int
}

// What the pedometer measured between two moments in the past week.
@MainActor
protocol PedometerHistory {
    func walked(from start: Date, to end: Date) async -> WalkedDistance?
}

@MainActor
final class CoreMotionPedometerHistory: PedometerHistory {
    func walked(from start: Date, to end: Date) async -> WalkedDistance? {
        guard CMPedometer.isStepCountingAvailable() else { return nil }
        let pedometer = CMPedometer()
        let result: WalkedDistance? = await withCheckedContinuation { continuation in
            // @Sendable: CMPedometer calls back on a background queue.
            pedometer.queryPedometerData(from: start, to: end) { @Sendable data, _ in
                continuation.resume(returning: data.map {
                    WalkedDistance(meters: $0.distance?.doubleValue ?? 0, steps: $0.numberOfSteps.intValue)
                })
            }
        }
        _ = pedometer // kept alive until the query has answered
        return result
    }
}

// Keeps the app running in the background while it decides whether to record: iOS only gives an app
// woken by a home event a few seconds, unless it's receiving location updates.
@MainActor
protocol KeepAwake {
    func start()
    func stop()
}

@MainActor
final class LocationKeepAwake: KeepAwake {
    private var task: Task<Void, Never>?

    func start() {
        guard task == nil else { return }
        task = Task { @MainActor in
            let serviceSession = CLServiceSession(authorization: .always)
            let backgroundSession = CLBackgroundActivitySession()
            defer {
                backgroundSession.invalidate()
                serviceSession.invalidate()
            }
            do {
                for try await _ in CLLocationUpdate.liveUpdates(.fitness) {} // ends when the task is cancelled
            } catch {}
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }
}
