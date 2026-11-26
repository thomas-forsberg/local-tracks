import Foundation
import Shared
import Testing
@testable import LocalTracks

struct ActivityGroupsTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        calendar.timeZone = TimeZone(identifier: "Europe/Oslo")!
        return calendar
    }()
    // Wednesday 25 November 2026.
    private let now = ISO8601DateFormatter().date(from: "2026-11-25T12:00:00+01:00")!
    private var nextId: Int64 = 1

    private mutating func activity(_ date: String, km: Double = 1) -> ActivitySummary {
        defer { nextId += 1 }
        let start = ISO8601DateFormatter().date(from: date)!
        let totals = ActivityTotals.companion.ofSeconds(
            activeTimeSeconds: 600, distanceMeters: km * 1000, pointCount: 0, elevationGainMeters: 0, movingTimeSeconds: 600, stepCount: nil
        )
        return ActivitySummary(id: nextId, sport: .hiking, startedAt: .from(start), finishedAt: .from(start), totals: totals, autoStarted: false, leadIn: nil, activeKcalPerKg: nil, suspectedCar: false)
    }

    @Test mutating func thisWeekLastWeekEachMonthOfThisYearThenEachYear() {
        let activities = [
            activity("2026-11-23T08:00:00+01:00", km: 2), // Monday this week
            activity("2026-11-22T20:00:00+01:00", km: 3), // Sunday last week
            activity("2026-11-16T07:00:00+01:00", km: 4), // Monday last week
            activity("2026-11-15T10:00:00+01:00"),        // earlier in November
            activity("2026-10-03T10:00:00+02:00"),
            activity("2026-10-01T10:00:00+02:00"),
            activity("2026-01-01T10:00:00+01:00"),
            activity("2025-12-31T10:00:00+01:00"),
            activity("2024-06-01T10:00:00+02:00"),
        ]

        let groups = ActivityGroup.grouping(activities, now: now, calendar: calendar)

        let english = Locale(identifier: "en")
        #expect(groups.map { $0.title(locale: english, calendar: calendar) } == ["This week", "Last week", "November", "October", "January", "2025", "2024"])
        #expect(groups.map(\.activities.count) == [1, 2, 1, 2, 1, 1, 1])
        #expect(groups[1].distanceMeters == 7000)
        #expect(groups.map(\.startsExpanded) == [true, false, false, false, false, false, false])
    }

    @Test mutating func monthsAreCapitalizedInNorwegian() {
        let groups = ActivityGroup.grouping([activity("2026-10-03T10:00:00+02:00")], now: now, calendar: calendar)

        #expect(groups.first?.title(locale: Locale(identifier: "nb"), calendar: calendar) == "Oktober")
    }

    @Test func noActivitiesNoGroups() {
        #expect(ActivityGroup.grouping([], now: now, calendar: calendar).isEmpty)
    }
}
