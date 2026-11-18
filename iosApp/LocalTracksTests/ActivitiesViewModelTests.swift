import Foundation
import Shared
import Testing
@testable import LocalTracks

@MainActor
struct ActivitiesViewModelTests {
    private let environment: AppEnvironment

    init() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        environment = AppEnvironment(databaseDirectory: directory, stateStore: InMemoryRecordingStateStore(), locationSource: FakeLocationSource(), barometerSource: FakeBarometerSource())
    }

    private func record(_ sport: Sport) {
        environment.recording.start(sport)
        environment.recording.stop()
    }

    @Test func startsEmptyAndListsActivitiesNewestFirstAsTheyFinish() async {
        let viewModel = environment.activities
        let observing = Task { await viewModel.observe() }
        defer { observing.cancel() }
        #expect(await eventually { viewModel.activities?.isEmpty == true })

        record(.running)
        #expect(await eventually { viewModel.activities?.count == 1 })
        try? await Task.sleep(for: .milliseconds(5)) // distinct start times for a stable order
        record(.cycling)

        #expect(await eventually { viewModel.activities?.map(\.sport) == [.cycling, .running] })
    }

    @Test func doesNotListTheActivityBeingRecorded() async {
        let viewModel = environment.activities
        let observing = Task { await viewModel.observe() }
        defer { observing.cancel() }
        #expect(await eventually { viewModel.activities != nil })

        environment.recording.start(.hiking)

        try? await Task.sleep(for: .milliseconds(100))
        #expect(viewModel.activities?.isEmpty == true)
        environment.recording.stop()
        #expect(await eventually { viewModel.activities?.count == 1 })
    }

    @Test func deleteRemovesTheActivityFromTheListAndTheDatabase() async throws {
        let viewModel = environment.activities
        let observing = Task { await viewModel.observe() }
        defer { observing.cancel() }
        record(.hiking)
        let activity = try #require(await firstActivity(viewModel))

        viewModel.delete(activity)

        #expect(await eventually { viewModel.activities?.isEmpty == true })
        #expect(environment.repository.activity(id: activity.id) == nil)
    }

    private func firstActivity(_ viewModel: ActivitiesViewModel) async -> ActivitySummary? {
        _ = await eventually { viewModel.activities?.first != nil }
        return viewModel.activities?.first
    }
}
