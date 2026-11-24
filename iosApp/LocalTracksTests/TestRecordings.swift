import Foundation
import Shared
@testable import LocalTracks

extension AppEnvironment {
    // Records about 110 m northwards and stops: enough distance for the activity to be kept.
    func recordShortTrip(_ sport: Sport) {
        recorder.start(sport: sport)
        moveAlong()
        recorder.stop()
    }

    func moveAlong() {
        for (second, latitude) in [(1.0, 59.9), (2.0, 59.901)] {
            recorder.onLocation(fix: LocationFix(
                time: .from(.now.addingTimeInterval(second)),
                latitude: latitude,
                longitude: 10.7,
                horizontalAccuracyMeters: 5,
                altitudeMeters: nil,
                speedMetersPerSecond: nil
            ))
        }
    }
}
