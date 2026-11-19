import Shared
import SwiftUI

struct ActivityDetailView: View {
    @State var viewModel: ActivityDetailViewModel

    private var activity: ActivitySummary { viewModel.activity }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(activity.startedAt.date.formatted(date: .complete, time: .shortened))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                map
                    .frame(height: 340)
                    .clipShape(.rect(cornerRadius: 16))

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 20) {
                    Stat(title: "Distance", value: Formatters.distance(meters: activity.totals.distanceMeters))
                    Stat(title: "Moving time", value: Formatters.clock(seconds: activity.totals.movingTimeSeconds))
                    Stat(title: activity.sport.averageSpeedTitle, value: Formatters.speedOrPace(metersPerSecond: viewModel.averageSpeedMetersPerSecond, for: activity.sport))
                    Stat(title: "Climb", value: Formatters.elevation(meters: activity.totals.elevationGainMeters))
                    Stat(title: "Elapsed time", value: viewModel.elapsedSeconds.map(Formatters.clock(seconds:)) ?? "–")
                    Stat(title: "Max speed", value: Formatters.speed(metersPerSecond: viewModel.analysis?.maxSpeedMetersPerSecond?.doubleValue))
                }

                if let analysis = viewModel.analysis {
                    if analysis.profile.contains(where: { $0.elevationMeters != nil }) {
                        Section(title: "Elevation") { ElevationChart(profile: analysis.profile).frame(height: 160) }
                    }
                    if analysis.profile.contains(where: { $0.speedMetersPerSecond != nil }) {
                        Section(title: activity.sport.showsPace ? "Pace" : "Speed") {
                            SpeedChart(profile: analysis.profile, sport: activity.sport).frame(height: 160)
                        }
                    }
                    if !analysis.splits.isEmpty {
                        Section(title: "Splits") { SplitsTable(splits: analysis.splits, sport: activity.sport) }
                    }
                }
            }
            .padding()
        }
        .navigationTitle(activity.sport.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { viewModel.load() }
    }

    @ViewBuilder private var map: some View {
        switch viewModel.segments {
        case nil:
            Color.secondary.opacity(0.1).overlay(ProgressView())
        case let segments? where segments.allSatisfy(\.isEmpty):
            Color.secondary.opacity(0.1).overlay(Label("No GPS points", systemImage: "location.slash").foregroundStyle(.secondary))
        case let segments?:
            RouteMapView(segments: segments)
        }
    }
}

private struct Section<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            content
        }
        .padding(.top, 8)
    }
}

private struct Stat: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.weight(.semibold).monospacedDigit())
        }
        .accessibilityElement(children: .combine)
    }
}
