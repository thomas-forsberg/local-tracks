import Foundation
import Shared
import Testing
@testable import LocalTracks

@MainActor
struct LiveActivityControllerTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func progress() -> ActivityProgress {
        ActivityProgress.companion.startingAt(sport: .hiking, time: .from(start), departure: nil)
    }

    @Test func whileRecordingTheCardCountsUpFromWhenTheClockStarted() {
        let state = RecordingStateRecording(progress: progress(), resumedAt: .from(start))
        let now = start.addingTimeInterval(95)

        let content = LiveActivityController.contentState(for: state, now: now)

        #expect(content.status == .recording)
        #expect(content.activeSeconds == 95)
        #expect(content.timerStart == start)
    }

    @Test func pausedFreezesTheTime() {
        let state = RecordingStatePaused(progress: progress(), pausedAt: .from(start))

        let content = LiveActivityController.contentState(for: state, now: start.addingTimeInterval(600))

        #expect(content.status == .paused)
        #expect(content.timerStart == nil)
    }

    @Test func standingStillShowsAsAutoPaused() {
        let session = RecordingSession()
        session.start(sport: .hiking, departure: nil)
        _ = session.onLocation(fix: LocationFix(
            time: .from(.now.addingTimeInterval(1)), latitude: 59.9, longitude: 10.7,
            horizontalAccuracyMeters: 5, altitudeMeters: nil, speedMetersPerSecond: KotlinDouble(value: 0)
        ))

        #expect(LiveActivityController.contentState(for: session.state.value, now: .now).status == .autoPaused)
    }

    @Test func formatsPaceAndSpeedLikeTheApp() {
        #expect(LiveActivityFormat.speedOrPace(1000.0 / 631, showsPace: true) == "10:31 /km")
        #expect(LiveActivityFormat.speedOrPace(0.1, showsPace: true) == "–")
        #expect(LiveActivityFormat.speedOrPace(5, showsPace: false) == Formatters.speed(metersPerSecond: 5))
    }
}
