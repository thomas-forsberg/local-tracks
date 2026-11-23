import CoreLocation
import Observation
import Shared

@MainActor
@Observable
final class ActivityDetailViewModel {
    let activity: ActivitySummary
    // One coordinate list per segment. Nil until loaded.
    private(set) var segments: [[CLLocationCoordinate2D]]?
    // Charts, splits and max speed, computed in Kotlin from the same points. Nil until loaded.
    private(set) var analysis: ActivityAnalysis?

    // The route this activity follows, if it's been walked before (or since).
    private(set) var route: RouteSummary?

    @ObservationIgnored let repository: ActivityRepository
    @ObservationIgnored let routeLibrary: RouteLibrary?

    init(activity: ActivitySummary, repository: ActivityRepository, routes: RouteLibrary? = nil) {
        self.activity = activity
        self.repository = repository
        routeLibrary = routes
    }

    func loadRoute() async {
        guard let routeLibrary else { return }
        await routeLibrary.matchNewActivitiesInBackground()
        route = routeLibrary.routeFor(activityId: activity.id)
    }

    // "On Sognsvann rundt for the 5th time, 0:42 faster than your average."
    var routeSummaryLine: String? {
        guard let route, let stats = route.stats(sport: activity.sport),
              let index = route.attempts.filter({ $0.activity.sport == activity.sport }).firstIndex(where: { $0.activity.id == activity.id })
        else { return nil }
        let seconds = activity.totals.movingTimeSeconds - stats.averageMovingTimeSeconds
        return String(localized: "\(RouteFormat.ordinal(index + 1)) time, \(RouteFormat.versusAverage(seconds: seconds)).")
    }

    // Reads on the main actor, which is fine for walks (~700 points). A 4-hour ride is ~15k points:
    // measure that, and move the read off the main actor if opening the screen hitches.
    func load() {
        let points = repository.trackPoints(activityId: activity.id)
        segments = Self.segments(from: points)
        analysis = ActivityAnalysisKt.analyze(points: points, sport: activity.sport, maxSamples: 300)
    }

    // The stretch before GPS started, from where it began (home) to the first recorded point; drawn dashed.
    var leadInLine: [CLLocationCoordinate2D]? {
        guard let leadIn = activity.leadIn,
              let latitude = leadIn.startLatitude?.doubleValue, let longitude = leadIn.startLongitude?.doubleValue,
              let first = segments?.first?.first
        else { return nil }
        return [CLLocationCoordinate2D(latitude: latitude, longitude: longitude), first]
    }

    var elapsedSeconds: Double? {
        activity.finishedAt.map { $0.date.timeIntervalSince(activity.startedAt.date) }
    }

    var averageSpeedMetersPerSecond: Double? {
        let seconds = activity.totals.movingTimeSeconds
        return seconds > 0 ? activity.totals.distanceMeters / seconds : nil
    }

    // Points arrive ordered by sequence; consecutive points with the same segment index form one line.
    static func segments(from points: [RecordedPoint]) -> [[CLLocationCoordinate2D]] {
        var segments: [[CLLocationCoordinate2D]] = []
        var currentIndex: Int32?
        for recorded in points {
            let coordinate = CLLocationCoordinate2D(latitude: recorded.point.latitude, longitude: recorded.point.longitude)
            if recorded.segmentIndex == currentIndex {
                segments[segments.count - 1].append(coordinate)
            } else {
                segments.append([coordinate])
                currentIndex = recorded.segmentIndex
            }
        }
        return segments
    }
}
