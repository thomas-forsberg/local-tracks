import Foundation
import Shared

enum Formatters {
    static func distance(meters: Double, locale: Locale = .current) -> String {
        Measurement(value: meters / 1000, unit: UnitLength.kilometers)
            .formatted(.measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(2))).locale(locale))
    }

    static func elevation(meters: Double, locale: Locale = .current) -> String {
        Measurement(value: meters, unit: UnitLength.meters)
            .formatted(.measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(0))).locale(locale))
    }

    // Stopwatch style: "0:05", "44:00", "1:32:10".
    static func clock(seconds: Double) -> String {
        Duration.seconds(seconds.rounded(.down)).formatted(.time(pattern: seconds < 3600 ? .minuteSecond : .hourMinuteSecond))
    }

    // Compact, for lists: "9 sec", "44 min", "1 hr, 32 min" (localized).
    static func shortDuration(seconds: Double, locale: Locale = .current) -> String {
        let style = seconds < 60
            ? Duration.UnitsFormatStyle(allowedUnits: [.seconds], width: .abbreviated)
            : Duration.UnitsFormatStyle(allowedUnits: [.hours, .minutes], width: .abbreviated)
        let rounded = seconds < 60 ? seconds.rounded() : (seconds / 60).rounded() * 60
        return Duration.seconds(rounded).formatted(style.locale(locale))
    }

    static func speed(metersPerSecond: Double?, locale: Locale = .current) -> String {
        guard let metersPerSecond else { return "–" }
        return Measurement(value: metersPerSecond * 3.6, unit: UnitSpeed.kilometersPerHour)
            .formatted(.measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(1))).locale(locale))
    }

    // Minutes per kilometre, as runners and hikers expect: "10:31 /km".
    static func pace(metersPerSecond: Double?) -> String {
        // Slower than ~1 km/h means standing still; a pace like "56:00 /km" would only confuse.
        guard let metersPerSecond, metersPerSecond >= 0.3 else { return "–" }
        let secondsPerKilometer = Int((1000 / metersPerSecond).rounded())
        return "\(secondsPerKilometer / 60):\(String(format: "%02d", secondsPerKilometer % 60)) /km"
    }

    static func speedOrPace(metersPerSecond: Double?, for sport: Sport) -> String {
        sport.showsPace ? pace(metersPerSecond: metersPerSecond) : speed(metersPerSecond: metersPerSecond)
    }
}

extension Sport {
    var title: String {
        switch self {
        case .cycling: "Cycling"
        case .running: "Running"
        case .hiking: "Hiking"
        }
    }

    var systemImage: String {
        switch self {
        case .cycling: "figure.outdoor.cycle"
        case .running: "figure.run"
        case .hiking: "figure.hiking"
        }
    }

    var showsPace: Bool {
        switch self {
        case .cycling: false
        case .running, .hiking: true
        }
    }

    var currentSpeedTitle: String { showsPace ? "Pace" : "Speed" }
    var averageSpeedTitle: String { showsPace ? "Avg pace" : "Avg speed" }
}
