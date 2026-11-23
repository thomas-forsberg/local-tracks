import CoreLocation
import CoreMotion
import Shared

enum HomeEvent: Equatable, Sendable {
    case left(Date)
    case arrived(Date)
}

// Watches the circle around home. iOS keeps watching while the app isn't running, and relaunches it
// in the background for each crossing; that needs "Always" location access.
@MainActor
protocol HomeMonitoring {
    func events(home: HomeLocation, radius: Double) -> AsyncStream<HomeEvent>
    func stop() async
}

@MainActor
final class CoreLocationHomeMonitor: HomeMonitoring {
    private static let monitorName = "home"
    private static let conditionId = "home"

    func events(home: HomeLocation, radius: Double) -> AsyncStream<HomeEvent> {
        let center = CLLocationCoordinate2D(latitude: home.latitude, longitude: home.longitude)
        return AsyncStream { continuation in
            let task = Task {
                // Recreating the monitor by name picks up events iOS saved while the app wasn't running.
                let monitor = await CLMonitor(Self.monitorName)
                await monitor.add(CLMonitor.CircularGeographicCondition(center: center, radius: radius), identifier: Self.conditionId)
                do {
                    for try await event in await monitor.events {
                        switch event.state {
                        case .satisfied: continuation.yield(.arrived(event.date))
                        case .unsatisfied: continuation.yield(.left(event.date))
                        default: break
                        }
                    }
                } catch {}
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func stop() async {
        let monitor = await CLMonitor(Self.monitorName)
        await monitor.remove(Self.conditionId)
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
