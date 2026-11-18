#if DEBUG
import Foundation
import Shared

// Debug-only launch modes for UI tests and screenshots. They use a fresh temporary database,
// so they never touch real recordings.
//   -demoData       a few example activities
//   -demoDataEmpty  no activities
enum DemoMode {
    case sampleActivities
    case empty

    static func fromLaunchArguments(_ arguments: [String] = ProcessInfo.processInfo.arguments) -> DemoMode? {
        if arguments.contains("-demoData") { return .sampleActivities }
        if arguments.contains("-demoDataEmpty") { return .empty }
        return nil
    }

    @MainActor
    func makeEnvironment() throws -> AppEnvironment {
        let directory = FileManager.default.temporaryDirectory.appending(path: "demo-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let environment = AppEnvironment(databaseDirectory: directory)
        if self == .sampleActivities {
            DemoData.seed(environment.repository)
        }
        return environment
    }
}

enum DemoData {
    private struct Sample {
        let sport: Sport
        let start: String
        let minutes: Double
        let kilometers: Double
        let climb: Double
        let latitude: Double
        let longitude: Double
    }

    // Fixed dates and places, so screenshots look the same on every run.
    private static let samples = [
        Sample(sport: .hiking, start: "2026-11-16T09:12:00Z", minutes: 92, kilometers: 5.4, climb: 312, latitude: 59.9765, longitude: 10.7290),
        Sample(sport: .cycling, start: "2026-11-17T14:30:00Z", minutes: 66, kilometers: 23.8, climb: 186, latitude: 59.9139, longitude: 10.7522),
        Sample(sport: .running, start: "2026-11-18T06:45:00Z", minutes: 44, kilometers: 8.1, climb: 64, latitude: 59.2676, longitude: 10.4076),
    ]

    static func seed(_ repository: ActivityRepository) {
        for sample in samples {
            let startedAt = ISO8601DateFormatter().date(from: sample.start)!
            let id = repository.startActivity(sport: sample.sport, startedAt: .from(startedAt))
            let points = loop(around: sample, startingAt: startedAt)
            let totals = ActivityTotals.companion.ofSeconds(
                activeTimeSeconds: sample.minutes * 60,
                distanceMeters: sample.kilometers * 1000,
                pointCount: Int32(points.count),
                elevationGainMeters: sample.climb
            )
            repository.appendPoints(activityId: id, firstSeq: 0, points: points, totals: totals)
            repository.finishActivity(activityId: id, finishedAt: .from(startedAt.addingTimeInterval(sample.minutes * 60)), totals: totals)
        }
    }

    // A circular route of the sample's length, one point per 30 s.
    private static func loop(around sample: Sample, startingAt start: Date) -> [RecordedPoint] {
        let count = Int(sample.minutes * 2)
        let radiusMeters = sample.kilometers * 1000 / (2 * .pi)
        let metersPerDegreeLatitude = 111_195.0
        let metersPerDegreeLongitude = metersPerDegreeLatitude * cos(sample.latitude * .pi / 180)
        return (0..<count).map { index in
            let angle = 2 * Double.pi * Double(index) / Double(count)
            return RecordedPoint(
                segmentIndex: 0,
                point: TrackPoint(
                    latitude: sample.latitude + radiusMeters * sin(angle) / metersPerDegreeLatitude,
                    longitude: sample.longitude + radiusMeters * cos(angle) / metersPerDegreeLongitude,
                    elevationMeters: KotlinDouble(value: 150 + sample.climb / 2 * sin(angle)),
                    time: .from(start.addingTimeInterval(Double(index) * 30)),
                    horizontalAccuracyMeters: KotlinDouble(value: 5),
                    speedMetersPerSecond: nil,
                    barometer: nil
                )
            )
        }
    }
}
#endif
