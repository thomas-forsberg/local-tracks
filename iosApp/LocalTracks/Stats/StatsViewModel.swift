import Foundation
import Observation
import Shared

enum StatsPeriod: String, CaseIterable, Identifiable {
    case week = "Week"
    case month = "Month"
    case year = "Year"
    case allTime = "All time"

    var id: Self { self }

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

    @ObservationIgnored private let repository: ActivityRepository

    init(repository: ActivityRepository) {
        self.repository = repository
    }

    func observe() async {
        for await activities in repository.finishedActivities() {
            self.activities = activities
        }
    }

    func totals(now: Date = .now) -> [SportTotals] {
        StatsKt.totalsSince(activities: activities ?? [], since: period.start(containing: now).map(KotlinInstant.from))
    }

    var records: [PersonalRecord] {
        StatsKt.personalRecords(activities: activities ?? [])
    }

    func detail(for activity: ActivitySummary) -> ActivityDetailViewModel {
        ActivityDetailViewModel(activity: activity, repository: repository)
    }
}
