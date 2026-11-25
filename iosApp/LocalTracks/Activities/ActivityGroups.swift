import Foundation
import Shared

// The activity list in periods: this week, last week, then each earlier month of this year, then each
// earlier year. Only this week starts expanded.
struct ActivityGroup: Identifiable, Equatable {
    enum Period: Hashable {
        case thisWeek
        case lastWeek
        // The first day of the month or year.
        case month(Date)
        case year(Date)
    }

    let period: Period
    let activities: [ActivitySummary]

    var id: Period { period }
    var startsExpanded: Bool { period == .thisWeek }
    var distanceMeters: Double { activities.reduce(0) { $0 + $1.totals.distanceMeters } }

    // The calendar must be the one the groups were made with: a month starts at midnight in its time zone.
    func title(locale: Locale = .current, calendar: Calendar = .current) -> String {
        let style = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
        return switch period {
        case .thisWeek: String(localized: "This week")
        case .lastWeek: String(localized: "Last week")
        case let .month(start): start.formatted(style.month(.wide)).capitalized(with: locale)
        case let .year(start): start.formatted(style.year())
        }
    }

    static func == (lhs: ActivityGroup, rhs: ActivityGroup) -> Bool {
        lhs.period == rhs.period && lhs.activities.map(\.id) == rhs.activities.map(\.id)
    }

    // Activities newest first, as the list shows them; uses the user's calendar, so a Norwegian week starts on Monday.
    static func grouping(_ activities: [ActivitySummary], now: Date = .now, calendar: Calendar = .current) -> [ActivityGroup] {
        guard let thisWeek = calendar.dateInterval(of: .weekOfYear, for: now)?.start,
              let lastWeek = calendar.date(byAdding: .weekOfYear, value: -1, to: thisWeek),
              let thisYear = calendar.dateInterval(of: .year, for: now)?.start else { return [] }
        func period(of date: Date) -> Period {
            if date >= thisWeek { return .thisWeek }
            if date >= lastWeek { return .lastWeek }
            if date >= thisYear, let month = calendar.dateInterval(of: .month, for: date)?.start { return .month(month) }
            return .year(calendar.dateInterval(of: .year, for: date)?.start ?? date)
        }
        var groups: [ActivityGroup] = []
        for activity in activities {
            let period = period(of: activity.startedAt.date)
            if let last = groups.last, last.period == period {
                groups[groups.count - 1] = ActivityGroup(period: period, activities: last.activities + [activity])
            } else {
                groups.append(ActivityGroup(period: period, activities: [activity]))
            }
        }
        return groups
    }
}
