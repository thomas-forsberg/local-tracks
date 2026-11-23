import SwiftUI

@main
struct LocalTracksApp: App {
    // The delegate owns the environment, so a background relaunch can continue recording before any UI exists.
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            switch appDelegate.environment {
            case .success(let environment):
                RootView(environment: environment)
            case .failure(let error):
                // Only happens if the app can't create its own folder, e.g. when the disk is full.
                ContentUnavailableView("Can't open storage", systemImage: "externaldrive.badge.xmark", description: Text(error.localizedDescription))
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard case .success(let environment) = appDelegate.environment else { return }
            switch phase {
            case .background:
                // The app may be killed at any time once in the background, so write pending points now.
                environment.recording.flush()
            case .active:
                environment.liveActivity.appBecameActive()
            default:
                break
            }
        }
    }
}
