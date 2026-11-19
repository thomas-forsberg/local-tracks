import Foundation
import Shared
import Testing
@testable import LocalTracks

@MainActor
struct StatsViewModelTests {
    private var oslo: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Oslo")!
        calendar.firstWeekday = 2 // Monday
        return calendar
    }

    @Test func periodsStartAtTheUsersWeekMonthAndYear() {
        // Thursday 19 November 2026, 12:00 in Oslo.
        let thursday = ISO8601DateFormatter().date(from: "2026-11-19T11:00:00Z")!
        let formatter = ISO8601DateFormatter()

        #expect(StatsPeriod.week.start(containing: thursday, calendar: oslo).map(formatter.string) == "2026-11-15T23:00:00Z") // Monday 00:00 Oslo
        #expect(StatsPeriod.month.start(containing: thursday, calendar: oslo).map(formatter.string) == "2026-10-31T23:00:00Z")
        #expect(StatsPeriod.year.start(containing: thursday, calendar: oslo).map(formatter.string) == "2025-12-31T23:00:00Z")
        #expect(StatsPeriod.allTime.start(containing: thursday, calendar: oslo) == nil)
    }

    @Test func totalsFollowTheDatabase() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let environment = AppEnvironment(databaseDirectory: directory, stateStore: InMemoryRecordingStateStore(), locationSource: FakeLocationSource(), barometerSource: FakeBarometerSource())
        let viewModel = environment.stats
        let observing = Task { await viewModel.observe() }
        defer { observing.cancel() }

        environment.recording.start(.hiking)
        environment.recording.stop()

        #expect(await eventually { viewModel.totals().first?.activityCount == 1 })
        #expect(viewModel.totals().first?.sport == .hiking)
    }
}
