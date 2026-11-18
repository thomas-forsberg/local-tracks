import CoreMotion
import Shared

@MainActor
protocol BarometerSource {
    // Finishes immediately on devices without a barometer, such as the simulator.
    func readings() -> AsyncStream<BarometerReading>
}

@MainActor
final class CoreMotionBarometerSource: BarometerSource {
    // Owned here rather than captured by the stream: CMAltimeter isn't Sendable,
    // but this main-actor class is, so the termination handler can safely reach it.
    private var altimeter: CMAltimeter?

    func readings() -> AsyncStream<BarometerReading> {
        stop()
        return AsyncStream { continuation in
            guard CMAltimeter.isRelativeAltitudeAvailable() else {
                continuation.finish()
                return
            }
            let altimeter = CMAltimeter()
            self.altimeter = altimeter
            altimeter.startRelativeAltitudeUpdates(to: .main) { data, error in
                guard let data, error == nil else {
                    // Typically Motion & Fitness permission denied; recording continues without elevation data.
                    continuation.finish()
                    return
                }
                continuation.yield(.from(
                    relativeAltitudeMeters: data.relativeAltitude.doubleValue,
                    pressureKilopascals: data.pressure.doubleValue,
                    secondsSinceBoot: data.timestamp
                ))
            }
            continuation.onTermination = { _ in Task { @MainActor [weak self] in self?.stop() } }
        }
    }

    private func stop() {
        altimeter?.stopRelativeAltitudeUpdates()
        altimeter = nil
    }
}
