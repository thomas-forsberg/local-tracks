import Shared
import SwiftUI

extension RouteSummary {
    // The user's name for it, else its length: "2,51 km loop".
    var displayName: String {
        let length = Formatters.distance(meters: lengthMeters)
        return name ?? (shape == .notALoop ? String(localized: "\(length) route") : String(localized: "\(length) loop"))
    }

    // Which way round an attempt went, in words; nil when the route isn't a loop.
    func directionTitle(reversed: Bool) -> String {
        switch shape {
        case .clockwiseLoop: reversed ? String(localized: "Anticlockwise") : String(localized: "Clockwise")
        case .anticlockwiseLoop: reversed ? String(localized: "Clockwise") : String(localized: "Anticlockwise")
        case .notALoop: reversed ? String(localized: "The other way") : String(localized: "This way")
        }
    }
}

enum RouteFormat {
    // "0:42 faster" / "1:10 slower" / "same time".
    static func difference(seconds: Double) -> String {
        let time = Formatters.clock(seconds: abs(seconds))
        guard abs(seconds) >= 1 else { return String(localized: "same time") }
        return seconds < 0 ? String(localized: "\(time) faster") : String(localized: "\(time) slower")
    }

    // "1st", "23rd" in English, "1.", "23." in Norwegian.
    static func ordinal(_ number: Int, locale: Locale = .current) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .ordinal
        formatter.locale = locale
        return formatter.string(from: number as NSNumber) ?? "\(number)"
    }

    // How an attempt compares with the average: "0:42 faster than your average".
    static func versusAverage(seconds: Double) -> String {
        let time = Formatters.clock(seconds: abs(seconds))
        if abs(seconds) < 1 { return String(localized: "your average time") }
        return seconds < 0 ? String(localized: "\(time) faster than your average") : String(localized: "\(time) slower than your average")
    }
}

@MainActor
@Observable
final class RouteDetailViewModel {
    private(set) var route: RouteSummary
    var sport: Sport
    let reference: ActivityDetailViewModel

    @ObservationIgnored private let library: RouteLibrary
    @ObservationIgnored let repository: ActivityRepository

    init(route: RouteSummary, library: RouteLibrary, repository: ActivityRepository) {
        self.route = route
        self.library = library
        self.repository = repository
        sport = route.sports().first ?? .hiking
        reference = ActivityDetailViewModel(
            activity: route.attempts.first { $0.activity.id == route.referenceActivityId }?.activity ?? route.attempts[0].activity,
            repository: repository
        )
    }

    var sports: [Sport] { route.sports() }

    var stats: RouteStats? { route.stats(sport: sport) }

    func rename(to name: String) {
        library.rename(routeId: route.id, name: name)
        if let renamed = library.route(id: route.id) { route = renamed }
    }

    func detail(for activity: ActivitySummary) -> ActivityDetailViewModel {
        ActivityDetailViewModel(activity: activity, repository: repository, routes: library)
    }
}

struct RouteDetailView: View {
    @State var viewModel: RouteDetailViewModel
    @State private var renaming = false
    @State private var newName = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Group {
                    if let segments = viewModel.reference.segments {
                        TrackMap(segments: segments, leadIn: viewModel.reference.leadInLine)
                    } else {
                        Theme.surface
                    }
                }
                .frame(height: 260)
                .clipShape(.rect(cornerRadius: 16))

                if viewModel.sports.count > 1 {
                    Picker("Sport", selection: $viewModel.sport) {
                        ForEach(viewModel.sports, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }

                if let stats = viewModel.stats {
                    StatsGrid(stats: stats, route: viewModel.route)
                    if stats.byDirection.count > 1 {
                        RouteSection(title: "Directions") {
                            ForEach(stats.byDirection.keys.map(\.boolValue).sorted { !$0 && $1 }, id: \.self) { reversed in
                                if let direction = stats.byDirection[KotlinBoolean(value: reversed)] {
                                    AttemptRow(
                                        title: viewModel.route.directionTitle(reversed: reversed),
                                        detail: String(localized: "\(direction.count)× · best \(Formatters.clock(seconds: direction.best.activity.totals.movingTimeSeconds))")
                                    )
                                }
                            }
                        }
                    }
                    RouteSection(title: "Best times") {
                        ForEach(Array(stats.best.enumerated()), id: \.element.activity.id) { index, attempt in
                            NavigationLink {
                                ActivityDetailView(viewModel: viewModel.detail(for: attempt.activity))
                            } label: {
                                AttemptRow(
                                    title: "\(index + 1). \(Formatters.clock(seconds: attempt.activity.totals.movingTimeSeconds))",
                                    detail: attempt.activity.startedAt.date.formatted(date: .abbreviated, time: .omitted)
                                )
                            }
                        }
                    }
                }
            }
            .padding()
        }
        .foregroundStyle(Theme.ink)
        .background(Theme.background)
        .navigationTitle(viewModel.route.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Rename", systemImage: "pencil") {
                    newName = viewModel.route.name ?? ""
                    renaming = true
                }
            }
        }
        .alert("Name this route", isPresented: $renaming) {
            TextField(viewModel.route.displayName, text: $newName)
            Button("Save") { viewModel.rename(to: newName) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Leave it empty to describe it by its length.")
        }
        .task { viewModel.reference.load() }
    }
}

private struct StatsGrid: View {
    let stats: RouteStats
    let route: RouteSummary

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 18) {
            RouteStat(title: "Times", value: "\(stats.count)")
            RouteStat(title: "Average time", value: Formatters.clock(seconds: stats.averageMovingTimeSeconds))
            RouteStat(
                title: stats.sport.averageSpeedTitle,
                value: Formatters.speedOrPace(metersPerSecond: stats.averageSpeedMetersPerSecond?.doubleValue, for: stats.sport)
            )
            RouteStat(
                title: "Best time",
                value: Formatters.clock(seconds: stats.best[0].activity.totals.movingTimeSeconds),
                detail: stats.best[0].activity.startedAt.date.formatted(date: .abbreviated, time: .omitted)
            )
            RouteStat(
                title: "Last time",
                value: Formatters.clock(seconds: stats.latest.activity.totals.movingTimeSeconds),
                detail: RouteFormat.versusAverage(seconds: stats.latestVersusAverageSeconds)
            )
            RouteStat(
                title: "Last done",
                value: stats.lastDoneAt.date.formatted(.relative(presentation: .named)),
                detail: stats.averageDaysBetween.map { String(localized: "every \(Int($0.doubleValue.rounded())) days on average") }
            )
            RouteStat(title: "Total distance", value: Formatters.distance(meters: stats.totalDistanceMeters))
            RouteStat(title: "Total time", value: Formatters.shortDuration(seconds: stats.totalMovingTimeSeconds))
        }
    }
}

private struct RouteStat: View {
    let title: LocalizedStringKey
    let value: String
    var detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            StatLabel(title)
            Text(value)
                .font(.numbers(28))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let detail {
                Text(detail).font(.footnote).foregroundStyle(Theme.inkSecondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct RouteSection<Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.numbers(24, weight: .bold, relativeTo: .title3))
            VStack(spacing: 0) { content }
                .card()
        }
    }
}

private struct AttemptRow: View {
    let title: String
    let detail: String

    var body: some View {
        HStack {
            Text(title).font(.numbers(22, relativeTo: .body))
            Spacer()
            Text(detail).font(.subheadline).foregroundStyle(Theme.inkSecondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(.rect)
    }
}

// Swift sees the Kotlin library as not Sendable, so it can't be handed to async code from the main actor.
// It is safe to: matching runs one at a time behind a mutex, on its own background dispatcher.
private final class RouteMatchingRun: @unchecked Sendable {
    let library: RouteLibrary

    init(library: RouteLibrary) {
        self.library = library
    }

    func run() async {
        _ = try? await library.matchNewActivities()
    }
}

extension RouteLibrary {
    @MainActor
    func matchNewActivitiesInBackground() async {
        await RouteMatchingRun(library: self).run()
    }
}
