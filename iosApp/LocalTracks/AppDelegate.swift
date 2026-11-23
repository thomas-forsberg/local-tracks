import UIKit

// Owns the environment so it exists before the first scene, which matters when iOS relaunches
// the app in the background: there may be no scene at all, but recording must continue.
final class AppDelegate: NSObject, UIApplicationDelegate {
    let environment: Result<AppEnvironment, Error> = Result { try AppEnvironment.live() }

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        let relaunchedForLocation = Self.isBackgroundRelaunch(
            hasLocationLaunchKey: launchOptions?[.location] != nil,
            applicationState: application.applicationState
        )
        // Apple's guidance: recreate the location sessions as early as possible after such a relaunch.
        if relaunchedForLocation, case .success(let environment) = environment {
            environment.recording.continueAfterRelaunch()
        }
        // Also when relaunched for leaving or reaching home: the home monitor must be recreated at once
        // to receive the event that woke the app.
        if case .success(let environment) = environment {
            environment.autoRecord.resume()
        }
        return true
    }

    // iOS relaunches a killed app in the background for location while a background activity session
    // was running. A launch by the user is never in the background state. The app has no other
    // background launch reasons (no background fetch, push or background tasks).
    static func isBackgroundRelaunch(hasLocationLaunchKey: Bool, applicationState: UIApplication.State) -> Bool {
        hasLocationLaunchKey || applicationState == .background
    }
}
