import Shared
import SwiftUI

struct ActivityDetailView: View {
    @State var viewModel: ActivityDetailViewModel
    @AppStorage(BodyWeight.key) private var weightKilograms = 0.0

    private var activity: ActivitySummary { viewModel.activity }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(activity.startedAt.date.formatted(date: .complete, time: .shortened))
                    .font(.subheadline)
                    .foregroundStyle(Theme.inkSecondary)
                if let note = Self.autoRecordNote(for: activity) {
                    Label(note, systemImage: "figure.walk.departure")
                        .font(.footnote)
                        .foregroundStyle(Theme.inkSecondary)
                }

                map
                    .frame(height: 340)
                    .clipShape(.rect(cornerRadius: 16))

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 20) {
                    Stat(title: "Distance", value: Formatters.distance(meters: activity.totals.distanceMeters))
                    Stat(title: "Moving time", value: Formatters.clock(seconds: activity.totals.movingTimeSeconds))
                    if activity.sport.showsPace {
                        Stat(title: "Avg pace", value: Formatters.pace(metersPerSecond: viewModel.averageSpeedMetersPerSecond))
                    }
                    Stat(title: "Avg speed", value: Formatters.speed(metersPerSecond: viewModel.averageSpeedMetersPerSecond))
                    Stat(title: "Climb", value: Formatters.elevation(meters: activity.totals.elevationGainMeters))
                    Stat(title: "Elapsed time", value: viewModel.elapsedSeconds.map(Formatters.clock(seconds:)) ?? "–")
                    Stat(title: "Max speed", value: Formatters.speed(metersPerSecond: viewModel.analysis?.maxSpeedMetersPerSecond?.doubleValue))
                    if activity.sport.countsSteps, let steps = activity.totals.stepCount {
                        Stat(title: "Steps", value: Formatters.steps(steps.intValue))
                    }
                    if activity.activeKcalPerKg != nil {
                        Stat(title: "Calories", value: BodyWeight.kcal(perKg: activity.activeKcalPerKg?.doubleValue, weightKilograms: weightKilograms).map { Formatters.calories(kcal: $0) } ?? "–")
                    }
                }
                if activity.activeKcalPerKg != nil && weightKilograms <= 0 {
                    Text("Add your weight in Settings to see calories.")
                        .font(.footnote)
                        .foregroundStyle(Theme.inkSecondary)
                }

                if let route = viewModel.route, let line = viewModel.routeSummaryLine, let library = viewModel.routeLibrary {
                    NavigationLink {
                        RouteDetailView(viewModel: RouteDetailViewModel(route: route, library: library, repository: viewModel.repository))
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "arrow.triangle.turn.up.right.circle")
                                .font(.title2)
                                .foregroundStyle(Theme.accent)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(route.displayName).font(.headline)
                                Text(line).font(.subheadline).foregroundStyle(Theme.inkSecondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(Theme.inkSecondary)
                        }
                        .padding(14)
                        .card()
                    }
                    .buttonStyle(.plain)
                }

                if let analysis = viewModel.analysis {
                    if analysis.profile.contains(where: { $0.elevationMeters != nil }) {
                        Section(title: "Elevation") { ElevationChart(profile: analysis.profile).frame(height: 160) }
                    }
                    if analysis.profile.contains(where: { $0.speedMetersPerSecond != nil }) {
                        SpeedSection(profile: analysis.profile, sport: activity.sport)
                    }
                    if !analysis.splits.isEmpty {
                        Section(title: "Splits") { SplitsTable(splits: analysis.splits, sport: activity.sport) }
                    }
                }
            }
            .padding()
        }
        .foregroundStyle(Theme.ink)
        .background(Theme.background)
        .navigationTitle(activity.sport.title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            viewModel.load()
            await viewModel.loadRoute()
        }
    }

    // The stretch before GPS started isn't drawn (it would show where the user lives), so it's described.
    static func autoRecordNote(for activity: ActivitySummary) -> String? {
        guard activity.autoStarted else { return nil }
        guard let leadIn = activity.leadIn, leadIn.distanceMeters > 0 else { return String(localized: "Started automatically when you left home") }
        let meters = Measurement(value: leadIn.distanceMeters.rounded(), unit: UnitLength.meters)
            .formatted(.measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(0))))
        return String(localized: "Started automatically. Includes \(meters) walked before GPS started, shown dashed.")
    }

    @ViewBuilder private var map: some View {
        switch viewModel.segments {
        case nil:
            Color.secondary.opacity(0.1).overlay(ProgressView())
        case let segments? where segments.allSatisfy(\.isEmpty):
            Color.secondary.opacity(0.1).overlay(Label("No GPS points", systemImage: "location.slash").foregroundStyle(.secondary))
        case let segments?:
            TrackMap(segments: segments, leadIn: viewModel.leadInLine)
        }
    }
}

// Running and hiking can switch the chart between pace and speed; cycling shows speed only.
private struct SpeedSection: View {
    let profile: [ProfileSample]
    let sport: Sport
    @State private var showsPace = true

    var body: some View {
        let showsPace = sport.showsPace && showsPace
        Section(title: sport.showsPace ? LocalizedStringKey("Pace and speed") : LocalizedStringKey("Speed")) {
            if sport.showsPace {
                Picker("Show", selection: $showsPace) {
                    Text("Pace").tag(true)
                    Text("Speed").tag(false)
                }
                .pickerStyle(.segmented)
            }
            SpeedChart(profile: profile, showsPace: showsPace, color: sport.color).frame(height: 160)
        }
    }
}

private struct Section<Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.numbers(24, weight: .bold, relativeTo: .title3))
            content
        }
        .padding(.top, 8)
    }
}

private struct Stat: View {
    let title: LocalizedStringKey
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            StatLabel(title)
            Text(value)
                .font(.numbers(30))
        }
        .accessibilityElement(children: .combine)
    }
}
