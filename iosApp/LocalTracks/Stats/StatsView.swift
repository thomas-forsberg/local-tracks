import Shared
import SwiftUI

struct StatsView: View {
    @Bindable var viewModel: StatsViewModel

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Period", selection: $viewModel.period) {
                        ForEach(StatsPeriod.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())

                    let totals = viewModel.totals()
                    if totals.isEmpty {
                        Text("No activities in this period.").foregroundStyle(.secondary)
                    }
                    ForEach(totals, id: \.sport) { TotalsRow(totals: $0) }
                }

                let records = viewModel.records
                if !records.isEmpty {
                    ForEach(Sport.allCases, id: \.self) { sport in
                        let ofSport = records.filter { $0.activity.sport == sport }
                        if !ofSport.isEmpty {
                            Section("\(sport.title) records") {
                                ForEach(ofSport, id: \.kind) { record in
                                    NavigationLink(value: record.activity) { RecordRow(record: record) }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Stats")
            .navigationDestination(for: ActivitySummary.self) { activity in
                ActivityDetailView(viewModel: viewModel.detail(for: activity))
            }
        }
        .task { await viewModel.observe() }
    }
}

private struct TotalsRow: View {
    let totals: SportTotals

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: totals.sport.systemImage)
                .font(.title2)
                .frame(width: 36)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 4) {
                Text("\(totals.sport.title) · \(totals.activityCount) \(totals.activityCount == 1 ? "activity" : "activities")")
                    .font(.headline)
                Text([
                    Formatters.distance(meters: totals.distanceMeters),
                    Formatters.shortDuration(seconds: totals.movingTimeSeconds),
                    "↑ " + Formatters.elevation(meters: totals.elevationGainMeters),
                ].joined(separator: " · "))
                    .font(.subheadline.monospacedDigit())
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

private struct RecordRow: View {
    let record: PersonalRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(record.kind.title)
                Spacer()
                Text(value).font(.body.weight(.semibold).monospacedDigit())
            }
            Text(record.activity.startedAt.date.formatted(date: .abbreviated, time: .omitted))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var value: String {
        switch record.kind {
        case .longestDistance: Formatters.distance(meters: record.value)
        case .longestMovingTime: Formatters.clock(seconds: record.value)
        case .biggestClimb: Formatters.elevation(meters: record.value)
        case .fastestAverageSpeed: Formatters.speedOrPace(metersPerSecond: record.value, for: record.activity.sport)
        }
    }
}

extension RecordKind {
    var title: String {
        switch self {
        case .longestDistance: "Longest distance"
        case .longestMovingTime: "Longest moving time"
        case .biggestClimb: "Biggest climb"
        case .fastestAverageSpeed: "Fastest average"
        }
    }
}
