import Foundation
import Shared

// iOS storage for the Kotlin RecordingStateStore. UserDefaults hands writes to a system process
// right away, so the flag survives the app being killed straight after a pause.
final class UserDefaultsRecordingStateStore: NSObject, RecordingStateStore {
    private let defaults: UserDefaults
    private let key = "recording.pausedActivityId"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func pausedActivityId() -> KotlinLong? {
        (defaults.object(forKey: key) as? NSNumber).map { KotlinLong(value: $0.int64Value) }
    }

    func markPaused(activityId: Int64) {
        defaults.set(activityId, forKey: key)
    }

    func clear() {
        defaults.removeObject(forKey: key)
    }
}
