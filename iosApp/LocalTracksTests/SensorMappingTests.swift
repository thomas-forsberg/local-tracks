import CoreLocation
import Foundation
import Shared
import Testing
@testable import LocalTracks

struct SensorMappingTests {
    private let timestamp = Date(timeIntervalSince1970: 1_789_196_400.123)

    private func location(
        horizontalAccuracy: Double = 4.5,
        verticalAccuracy: Double = 3,
        speed: Double = 5.25
    ) -> CLLocation {
        CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 59.9765, longitude: 10.729),
            altitude: 184.2,
            horizontalAccuracy: horizontalAccuracy,
            verticalAccuracy: verticalAccuracy,
            course: 90,
            speed: speed,
            timestamp: timestamp
        )
    }

    @Test func mapsAValidLocation() {
        let fix = LocationFix.from(location())

        #expect(fix.time.toEpochMilliseconds() == 1_789_196_400_123)
        #expect(fix.latitude == 59.9765)
        #expect(fix.longitude == 10.729)
        #expect(fix.horizontalAccuracyMeters == 4.5)
        #expect(fix.altitudeMeters?.doubleValue == 184.2)
        #expect(fix.speedMetersPerSecond?.doubleValue == 5.25)
    }

    @Test func negativeSpeedMeansUnknown() {
        #expect(LocationFix.from(location(speed: -1)).speedMetersPerSecond == nil)
    }

    @Test(arguments: [0.0, -1.0])
    func altitudeIsOnlyKeptWithValidVerticalAccuracy(verticalAccuracy: Double) {
        #expect(LocationFix.from(location(verticalAccuracy: verticalAccuracy)).altitudeMeters == nil)
    }

    @Test func invalidHorizontalAccuracyIsPassedThroughForTheKotlinFilter() {
        #expect(LocationFix.from(location(horizontalAccuracy: -1)).horizontalAccuracyMeters == -1)
    }

    @Test func instantRoundTripsWithMillisecondPrecision() {
        #expect(KotlinInstant.from(timestamp).date == timestamp)
    }

    @Test func barometerTimestampIsConvertedFromTimeSinceBoot() {
        let reading = BarometerReading.from(
            relativeAltitudeMeters: 2.5,
            pressureKilopascals: 99.1,
            secondsSinceBoot: 998,
            systemUptime: 1000,
            now: timestamp
        )

        #expect(reading.time.date == timestamp.addingTimeInterval(-2))
        #expect(reading.relativeAltitudeMeters == 2.5)
        #expect(reading.pressureKilopascals == 99.1)
    }
}
