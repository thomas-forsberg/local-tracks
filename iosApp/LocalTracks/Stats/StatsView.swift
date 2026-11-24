import Shared
import SwiftUI

struct StatsView: View {
    @Bindable var viewModel: StatsViewModel

    var body: some View {
        NavigationStack {
            List {
                // The picker is the header, not a row: as a transparent first row it took the section's
                // rounded top corners, and the totals box looked cut off.
                Section {
                    let totals = viewModel.totals()
                    if totals.isEmpty {
                        Text("No activities in this period.")
                            .foregroundStyle(Theme.inkSecondary)
                            .listRowBackground(Theme.surface)
                    }
                    ForEach(totals, id: \.sport) { TotalsRow(totals: $0).listRowBackground(Theme.surface) }
                } header: {
                    Picker("Period", selection: $viewModel.period) {
                        ForEach(StatsPeriod.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .textCase(nil)
                    .padding(.bottom, 8)
                }

                if !viewModel.routes.isEmpty {
                    Section("Routes") {
                        ForEach(viewModel.routes, id: \.id) { route in
                            NavigationLink {
                                RouteDetailView(viewModel: viewModel.detail(for: route))
                            } label: {
                                RouteRow(route: route, preview: viewModel.preview(for: route))
                            }
                            .listRowBackground(Theme.surface)
                        }
                    }
                }

                let records = viewModel.records
                if !records.isEmpty {
                    ForEach(Sport.allCases, id: \.self) { sport in
                        let ofSport = records.filter { $0.activity.sport == sport }
                        if !ofSport.isEmpty {
                            Section("\(sport.title) records") {
                                ForEach(ofSport, id: \.kind) { record in
                                    NavigationLink(value: record.activity) { RecordRow(record: record) }
                                        .listRowBackground(Theme.surface)
                                }
                            }
                        }
                    }
                }
            }
            .themedList()
            .navigationTitle("Stats")
            .navigationDestination(for: ActivitySummary.self) { activity in
                ActivityDetailView(viewModel: viewModel.detail(for: activity))
            }
        }
        .task { await viewModel.observe() }
    }
}

private struct RouteRow: View {
    let route: RouteSummary
    let preview: RoutePreview?

    var body: some View {
        let sport = route.sports().first ?? .hiking
        let stats = route.stats(sport: sport)
        HStack(spacing: 16) {
            RouteThumbnail(preview: preview, sport: sport)
                .frame(width: 64, height: 64)
            VStack(alignment: .leading, spacing: 4) {
                Text(route.displayName).font(.headline)
                if let stats {
                    Text(String(localized: "\(stats.count)× · best \(Formatters.clock(seconds: stats.best[0].activity.totals.movingTimeSeconds))"))
                        .font(.numbers(20, relativeTo: .body))
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

private struct TotalsRow: View {
    let totals: SportTotals

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: totals.sport.systemImage)
                .font(.title2)
                .frame(width: 36)
                .foregroundStyle(totals.sport.color)
            VStack(alignment: .leading, spacing: 4) {
                Text("\(totals.sport.title) · \(String(localized: "\(totals.activityCount) activities"))")
                    .font(.headline)
                Text([
                    Formatters.distance(meters: totals.distanceMeters),
                    Formatters.shortDuration(seconds: totals.movingTimeSeconds),
                    "↑ " + Formatters.elevation(meters: totals.elevationGainMeters),
                ].joined(separator: " · "))
                    .font(.numbers(20, relativeTo: .body))
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
        case .longestDistance: String(localized: "Longest distance")
        case .longestMovingTime: String(localized: "Longest moving time")
        case .biggestClimb: String(localized: "Biggest climb")
        case .fastestAverageSpeed: String(localized: "Fastest average")
        }
    }
}
