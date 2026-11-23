import Observation
import Shared

@MainActor
@Observable
final class ActivitiesViewModel {
    // Finished activities, newest first. Nil until the first database read, so the view can tell
    // "loading" apart from "no activities".
    private(set) var activities: [ActivitySummary]?

    @ObservationIgnored private let repository: ActivityRepository
    @ObservationIgnored let routeLibrary: RouteLibrary
    // Route shapes by activity id; a finished activity's points never change.
    @ObservationIgnored private var previews: [Int64: RoutePreview?] = [:]

    init(repository: ActivityRepository, routes: RouteLibrary) {
        self.repository = repository
        routeLibrary = routes
    }

    // Follows the database until the calling task is cancelled (SwiftUI's .task does that when the view goes away).
    // The Kotlin Flow re-emits whenever the activity table changes, e.g. when a recording is stopped or deleted.
    func observe() async {
        for await activities in repository.finishedActivities() {
            self.activities = activities
        }
    }

    func detail(for activity: ActivitySummary) -> ActivityDetailViewModel {
        ActivityDetailViewModel(activity: activity, repository: repository, routes: routeLibrary)
    }

    func routePreview(for activity: ActivitySummary) -> RoutePreview? {
        if let cached = previews[activity.id] { return cached }
        let preview = repository.routePreview(activityId: activity.id)
        previews[activity.id] = .some(preview)
        return preview
    }

    func delete(_ activity: ActivitySummary) {
        repository.delete(activityId: activity.id)
    }
}
