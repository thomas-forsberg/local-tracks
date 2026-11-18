import Foundation
import Testing
@testable import LocalTracks

struct UserDefaultsRecordingStateStoreTests {
    private let defaults = UserDefaults(suiteName: "tests.\(UUID().uuidString)")!

    @Test func remembersThePausedActivityAcrossInstances() {
        UserDefaultsRecordingStateStore(defaults: defaults).markPaused(activityId: 42)

        #expect(UserDefaultsRecordingStateStore(defaults: defaults).pausedActivityId()?.int64Value == 42)
    }

    @Test func clearForgetsIt() {
        let store = UserDefaultsRecordingStateStore(defaults: defaults)
        store.markPaused(activityId: 7)

        store.clear()

        #expect(store.pausedActivityId() == nil)
    }
}
