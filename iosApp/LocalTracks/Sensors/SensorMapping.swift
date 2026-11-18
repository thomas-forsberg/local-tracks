import CoreLocation
import Foundation
import Shared

extension KotlinInstant {
    static func from(_ date: Date) -> KotlinInstant {
        KotlinInstant.companion.fromEpochMilliseconds(epochMilliseconds: Int64((date.timeIntervalSince1970 * 1000).rounded()))
    }

    var date: Date {
        Date(timeIntervalSince1970: Double(toEpochMilliseconds()) / 1000)
    }
}

extension LocationFix {
    // CoreLocation marks unknown values with negative numbers rather than optionals.
    // Invalid horizontal accuracy is passed through on purpose: the Kotlin session owns that filter.
    static func from(_ location: CLLocation) -> LocationFix {
        LocationFix(
            time: .from(location.timestamp),
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            horizontalAccuracyMeters: location.horizontalAccuracy,
            altitudeMeters: location.verticalAccuracy > 0 ? KotlinDouble(value: location.altitude) : nil,
            speedMetersPerSecond: location.speed >= 0 ? KotlinDouble(value: location.speed) : nil
        )
    }
}

extension BarometerReading {
    // CMAltitudeData.timestamp counts seconds since the device booted, not wall-clock time.
    static func from(
        relativeAltitudeMeters: Double,
        pressureKilopascals: Double,
        secondsSinceBoot: TimeInterval,
        systemUptime: TimeInterval = ProcessInfo.processInfo.systemUptime,
        now: Date = .now
    ) -> BarometerReading {
        BarometerReading(
            time: .from(now.addingTimeInterval(secondsSinceBoot - systemUptime)),
            relativeAltitudeMeters: relativeAltitudeMeters,
            pressureKilopascals: pressureKilopascals
        )
    }
}
