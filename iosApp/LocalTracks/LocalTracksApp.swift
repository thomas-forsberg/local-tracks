import SwiftUI

@main
struct LocalTracksApp: App {
    @Environment(\.scenePhase) private var scenePhase
    private let environment: Result<AppEnvironment, Error> = Result { try AppEnvironment.live() }

    var body: some Scene {
        WindowGroup {
            switch environment {
            case .success(let environment):
                RecordView(controller: environment.recording)
            case .failure(let error):
                // Only happens if the app can't create its own folder, e.g. when the disk is full.
                ContentUnavailableView("Can't open storage", systemImage: "externaldrive.badge.xmark", description: Text(error.localizedDescription))
            }
        }
        .onChange(of: scenePhase) { _, phase in
            // The app may be killed at any time once in the background, so write pending points now.
            if phase == .background, case .success(let environment) = environment {
                environment.recording.flush()
            }
        }
    }
}
