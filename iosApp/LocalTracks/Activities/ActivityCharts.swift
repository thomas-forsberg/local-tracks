import Charts
import Shared
import SwiftUI

struct ElevationChart: View {
    let profile: [ProfileSample]

    private var points: [(km: Double, meters: Double)] {
        profile.compactMap { sample in sample.elevationMeters.map { (sample.distanceMeters / 1000, $0.doubleValue) } }
    }

    var body: some View {
        let points = points
        let low = (points.map(\.meters).min() ?? 0) - 5
        let high = (points.map(\.meters).max() ?? 0) + 5
        Chart(points.indices, id: \.self) { index in
            AreaMark(x: .value("km", points[index].km), yStart: .value("Base", low), yEnd: .value("Elevation", points[index].meters))
                .foregroundStyle(.green.opacity(0.25))
            LineMark(x: .value("km", points[index].km), y: .value("Elevation", points[index].meters))
                .foregroundStyle(.green)
        }
        .chartYScale(domain: low...high)
        .chartXAxisLabel("km")
        .chartYAxisLabel("m")
    }
}

// Speed in km/h, or pace in min/km with faster at the top.
// Pace is plotted negated so that faster is higher, with positive labels.
struct SpeedChart: View {
    let profile: [ProfileSample]
    let showsPace: Bool

    private var points: [(km: Double, value: Double)] {
        profile.compactMap { sample in
            guard let speed = sample.speedMetersPerSecond?.doubleValue, speed > 0 else { return nil }
            let value = showsPace ? -min(1000 / speed / 60, 30) : speed * 3.6
            return (sample.distanceMeters / 1000, value)
        }
    }

    var body: some View {
        let points = points
        Chart(points.indices, id: \.self) { index in
            LineMark(x: .value("km", points[index].km), y: .value(showsPace ? "min/km" : "km/h", points[index].value))
                .foregroundStyle(.blue)
                .interpolationMethod(.monotone)
        }
        .chartYScale(domain: Self.domain(for: points.map(\.value), minimumSpan: showsPace ? 2 : 10, floor: showsPace ? nil : 0))
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisValueLabel {
                    if let number = value.as(Double.self) {
                        Text(showsPace ? Self.minutesAndSeconds(-number) : number.formatted(.number.precision(.fractionLength(0))))
                    }
                }
            }
        }
        .chartXAxisLabel("km")
        .chartYAxisLabel(showsPace ? "min/km" : "km/h")
    }

    // A nearly constant pace would otherwise fill the chart with magnified noise.
    nonisolated static func domain(for values: [Double], minimumSpan: Double, floor: Double?) -> ClosedRange<Double> {
        let low = values.min() ?? 0
        let high = values.max() ?? minimumSpan
        let middle = (low + high) / 2
        let half = max((high - low) / 2, minimumSpan / 2)
        let bottom = floor.map { max($0, middle - half) } ?? (middle - half)
        return bottom...(middle + half)
    }

    nonisolated static func minutesAndSeconds(_ minutes: Double) -> String {
        let seconds = Int((minutes * 60).rounded())
        return "\(seconds / 60):\(String(format: "%02d", seconds % 60))"
    }
}

struct SplitsTable: View {
    let splits: [Split]
    let sport: Sport

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
            GridRow {
                Text("Km")
                if sport.showsPace { Text("Pace") }
                Text("Speed")
                Text("Time")
                Text("Elev")
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
            ForEach(splits, id: \.number) { split in
                GridRow {
                    Text(split.distanceMeters >= 999.5 ? "\(split.number)" : Formatters.distance(meters: split.distanceMeters))
                    if sport.showsPace { Text(Formatters.pace(metersPerSecond: split.averageSpeedMetersPerSecond?.doubleValue)) }
                    Text(Formatters.speed(metersPerSecond: split.averageSpeedMetersPerSecond?.doubleValue))
                    Text(Formatters.clock(seconds: split.movingTimeSeconds))
                    Text(split.elevationChangeMeters.map { (($0.doubleValue >= 0 ? "+" : "") + Formatters.elevation(meters: $0.doubleValue)) } ?? "–")
                }
                .font(.callout.monospacedDigit())
            }
        }
    }
}
