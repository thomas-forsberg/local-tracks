import Observation
import Shared

@MainActor
@Observable
final class ActivitiesViewModel {
    // Finished activities, newest first. Nil until the first database read, so the view can tell
    // "loading" apart from "no activities".
    private(set) var activities: [ActivitySummary]?

    @ObservationIgnored private let repository: ActivityRepository

    init(repository: ActivityRepository) {
        self.repository = repository
    }

    // Follows the database until the calling task is cancelled (SwiftUI's .task does that when the view goes away).
    // The Kotlin Flow re-emits whenever the activity table changes, e.g. when a recording is stopped or deleted.
    func observe() async {
        for await activities in repository.finishedActivities() {
            self.activities = activities
        }
    }

    func delete(_ activity: ActivitySummary) {
        repository.delete(activityId: activity.id)
    }
}
