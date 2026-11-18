import CoreLocation
import Shared

enum LocationProblem: Equatable {
    case permissionDenied
    // The user turned off Precise Location; fixes are kilometres off and get filtered out.
    case approximateLocationOnly
    case unavailable
}

enum LocationEvent {
    case fix(LocationFix)
    case problem(LocationProblem)
}

@MainActor
protocol LocationSource {
    // Location stops when the consumer stops iterating (its task is cancelled).
    func events(for sport: Sport) -> AsyncStream<LocationEvent>
}

@MainActor
final class CoreLocationSource: LocationSource {
    func events(for sport: Sport) -> AsyncStream<LocationEvent> {
        let configuration = sport.liveConfiguration
        return AsyncStream { continuation in
            let task = Task { @MainActor in
                // Both sessions must live as long as the recording:
                // the service session holds the When In Use authorization,
                // the background session keeps updates coming with the screen locked.
                let serviceSession = CLServiceSession(authorization: .whenInUse)
                let backgroundSession = CLBackgroundActivitySession()
                defer {
                    backgroundSession.invalidate()
                    serviceSession.invalidate()
                }
                do {
                    for try await update in CLLocationUpdate.liveUpdates(configuration) {
                        if let event = LocationEvent(update) {
                            continuation.yield(event)
                        }
                    }
                } catch {
                    continuation.yield(.problem(.unavailable))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

extension LocationEvent {
    init?(_ update: CLLocationUpdate) {
        if update.authorizationDenied || update.authorizationDeniedGlobally || update.authorizationRestricted {
            self = .problem(.permissionDenied)
        } else if update.accuracyLimited {
            self = .problem(.approximateLocationOnly)
        } else if let location = update.location {
            self = .fix(.from(location))
        } else if update.locationUnavailable {
            self = .problem(.unavailable)
        } else {
            return nil
        }
    }
}

extension Sport {
    // Tells iOS what kind of movement to expect, which tunes its filtering.
    var liveConfiguration: CLLocationUpdate.LiveConfiguration {
        switch self {
        case .cycling: .otherNavigation
        case .running, .hiking: .fitness
        }
    }
}
