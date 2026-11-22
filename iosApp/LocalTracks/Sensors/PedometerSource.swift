import CoreMotion

@MainActor
protocol PedometerSource {
    // Running total of steps since the call. Finishes immediately without a pedometer (the simulator)
    // or without Motion & Fitness permission.
    func stepCounts() -> AsyncStream<Int>
}

@MainActor
final class CoreMotionPedometerSource: PedometerSource {
    // Owned here rather than captured by the stream: CMPedometer isn't Sendable,
    // but this main-actor class is, so the termination handler can safely reach it.
    private var pedometer: CMPedometer?

    func stepCounts() -> AsyncStream<Int> {
        stop()
        return AsyncStream { continuation in
            guard CMPedometer.isStepCountingAvailable() else {
                continuation.finish()
                return
            }
            let pedometer = CMPedometer()
            self.pedometer = pedometer
            // @Sendable: CMPedometer calls this on a background queue, so it must not be main-actor isolated.
            pedometer.startUpdates(from: .now) { @Sendable data, error in
                guard let data, error == nil else {
                    continuation.finish()
                    return
                }
                continuation.yield(data.numberOfSteps.intValue)
            }
            continuation.onTermination = { _ in Task { @MainActor [weak self] in self?.stop() } }
        }
    }

    private func stop() {
        pedometer?.stopUpdates()
        pedometer = nil
    }
}
