import ActivityKit
import AppIntents
import Foundation

// The lock-screen card and Dynamic Island while recording. Compiled into both the app and the widget
// extension, which doesn't link the Kotlin framework: everything here is plain Swift.
struct RecordingActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable, Sendable {
        enum Status: String, Codable, Hashable {
            case recording, autoPaused, paused
        }

        var status: Status
        // While recording: when the clock would have started without pauses, so the card counts up on its own.
        var timerStart: Date?
        var activeSeconds: Double
        var distanceMeters: Double
        var averageSpeedMetersPerSecond: Double?
    }

    var sportName: String
    var sportSymbol: String
    // Pace for running and hiking, speed for cycling, as in the app.
    var showsPace: Bool
}

// Pause/Resume on the card. A LiveActivityIntent runs in the app's process, where the handler is set.
struct TogglePauseIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Pause or resume recording"

    @MainActor static var handler: (() -> Void)?

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        Self.handler?()
        return .result()
    }
}

enum LiveActivityFormat {
    static func distance(_ meters: Double) -> String {
        Measurement(value: meters / 1000, unit: UnitLength.kilometers)
            .formatted(.measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(2))))
    }

    static func clock(_ seconds: Double) -> String {
        Duration.seconds(seconds.rounded(.down)).formatted(.time(pattern: seconds < 3600 ? .minuteSecond : .hourMinuteSecond))
    }

    static func speedOrPace(_ metersPerSecond: Double?, showsPace: Bool) -> String {
        guard let metersPerSecond, metersPerSecond >= 0.3 else { return "–" }
        if showsPace {
            let secondsPerKilometer = Int((1000 / metersPerSecond).rounded())
            return "\(secondsPerKilometer / 60):\(String(format: "%02d", secondsPerKilometer % 60)) /km"
        }
        return Measurement(value: metersPerSecond * 3.6, unit: UnitSpeed.kilometersPerHour)
            .formatted(.measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(1))))
    }
}
