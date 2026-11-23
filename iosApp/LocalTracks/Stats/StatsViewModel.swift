import Foundation
import Observation
import SwiftUI
import Shared

enum StatsPeriod: String, CaseIterable, Identifiable {
    case week = "Week"
    case month = "Month"
    case year = "Year"
    case allTime = "All time"

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .week: "Week"
        case .month: "Month"
        case .year: "Year"
        case .allTime: "All time"
        }
    }

    // Uses the user's calendar, so a Norwegian week starts on Monday.
    func start(containing date: Date, calendar: Calendar = .current) -> Date? {
        switch self {
        case .week: calendar.dateInterval(of: .weekOfYear, for: date)?.start
        case .month: calendar.dateInterval(of: .month, for: date)?.start
        case .year: calendar.dateInterval(of: .year, for: date)?.start
        case .allTime: nil
        }
    }
}

@MainActor
@Observable
final class StatsViewModel {
    var period: StatsPeriod = .week
    private(set) var activities: [ActivitySummary]?
    // Routes walked more than once, most attempts first.
    private(set) var routes: [RouteSummary] = []

    @ObservationIgnored private let repository: ActivityRepository
    @ObservationIgnored let routeLibrary: RouteLibrary

    init(repository: ActivityRepository, routes: RouteLibrary) {
        self.repository = repository
        routeLibrary = routes
    }

    func observe() async {
        for await activities in repository.finishedActivities() {
            self.activities = activities
            // New or deleted activities may change the routes; matching only checks what's new.
            await routeLibrary.matchNewActivitiesInBackground()
            routes = routeLibrary.routes().sorted { $0.attempts.count > $1.attempts.count }
        }
    }

    func totals(now: Date = .now) -> [SportTotals] {
        StatsKt.totalsSince(activities: activities ?? [], since: period.start(containing: now).map(KotlinInstant.from))
    }

    var records: [PersonalRecord] {
        StatsKt.personalRecords(activities: activities ?? [])
    }

    func detail(for route: RouteSummary) -> RouteDetailViewModel {
        RouteDetailViewModel(route: route, library: routeLibrary, repository: repository)
    }

    func detail(for activity: ActivitySummary) -> ActivityDetailViewModel {
        ActivityDetailViewModel(activity: activity, repository: repository, routes: routeLibrary)
    }
}
