import Foundation
import Shared

enum Formatters {
    static func distance(meters: Double) -> String {
        Measurement(value: meters / 1000, unit: UnitLength.kilometers)
            .formatted(.measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(2))))
    }

    static func elevation(meters: Double) -> String {
        Measurement(value: meters, unit: UnitLength.meters)
            .formatted(.measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(0))))
    }

    static func duration(seconds: Double) -> String {
        Duration.seconds(seconds).formatted(.time(pattern: .hourMinuteSecond))
    }

    static func speed(metersPerSecond: Double?) -> String {
        guard let metersPerSecond else { return "–" }
        return Measurement(value: metersPerSecond * 3.6, unit: UnitSpeed.kilometersPerHour)
            .formatted(.measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(1))))
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
}
