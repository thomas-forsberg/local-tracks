import CoreMotion

@MainActor
protocol MotionSource {
    // true: standing still, false: moving, nil: unknown. Finishes immediately without motion
    // hardware (the simulator) or without Motion & Fitness permission.
    func stationaryStates() -> AsyncStream<Bool?>
}

// iOS's motion classifier works from the accelerometer, independent of GPS, so it can tell
// "standing still" even while GPS drift suggests movement.
@MainActor
final class CoreMotionActivitySource: MotionSource {
    // Owned here rather than captured by the stream: CMMotionActivityManager isn't Sendable,
    // but this main-actor class is, so the termination handler can safely reach it.
    private var manager: CMMotionActivityManager?

    func stationaryStates() -> AsyncStream<Bool?> {
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
                continuation.yield(Self.stationary(activity))
            }
            continuation.onTermination = { _ in Task { @MainActor [weak self] in self?.stop() } }
        }
    }

    // Low-confidence guesses count as unknown, so GPS speed decides.
    nonisolated static func stationary(_ activity: CMMotionActivity) -> Bool? {
        guard activity.confidence != .low else { return nil }
        if activity.walking || activity.running || activity.cycling || activity.automotive { return false }
        return activity.stationary ? true : nil
    }

    private func stop() {
        manager?.stopActivityUpdates()
        manager = nil
    }
}
