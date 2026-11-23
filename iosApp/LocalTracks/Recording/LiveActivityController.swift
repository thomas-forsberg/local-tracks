import ActivityKit
import Foundation
import Shared

// ActivityKit.Activity is spelled out: the Kotlin framework also has an Activity (the database row).

// Keeps the lock-screen card in step with the recording: started with it, updated every few seconds
// (the time counts by itself), ended with it.
@MainActor
final class LiveActivityController {
    private let recording: RecordingController
    private let updateInterval: TimeInterval
    private var activity: ActivityKit.Activity<RecordingActivityAttributes>?
    private var lastSent: (status: RecordingActivityAttributes.ContentState.Status, at: Date)?

    init(recording: RecordingController, updateInterval: TimeInterval = 5) {
        self.recording = recording
        self.updateInterval = updateInterval
        // After a relaunch mid-recording the card from before is still showing.
        activity = ActivityKit.Activity<RecordingActivityAttributes>.activities.first
        TogglePauseIntent.handler = { [weak recording] in recording?.togglePause() }
    }

    // Called on every recording change; sends at most one update per interval unless the status changed.
    func recordingChanged(now: Date = .now) {
        let state = recording.state
        guard let progress = state.progressOrNull(), !(state is RecordingStateFinished) else {
            end()
            return
        }
        let content = Self.contentState(for: state, now: now)
        guard let activity else {
            start(sport: progress.sport, content: content, now: now)
            return
        }
        if let lastSent, lastSent.status == content.status, now.timeIntervalSince(lastSent.at) < updateInterval { return }
        lastSent = (content.status, now)
        // Looked up again off the main actor: ActivityKit's Activity isn't Sendable, its id is.
        let id = activity.id
        Task.detached {
            await Self.activity(id: id)?.update(ActivityContent(state: content, staleDate: nil))
        }
    }

    // iOS only lets the app start a card while it's in the foreground, so an automatic recording that
    // started in the background gets its card when the app is next opened.
    func appBecameActive() {
        lastSent = nil
        recordingChanged()
    }

    private func start(sport: Sport, content: RecordingActivityAttributes.ContentState, now: Date) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let attributes = RecordingActivityAttributes(sportName: sport.title, sportSymbol: sport.systemImage, showsPace: sport.showsPace)
        activity = try? ActivityKit.Activity.request(attributes: attributes, content: ActivityContent(state: content, staleDate: nil))
        if activity != nil { lastSent = (content.status, now) }
    }

    private func end() {
        activity = nil
        lastSent = nil
        guard !ActivityKit.Activity<RecordingActivityAttributes>.activities.isEmpty else { return }
        Task.detached {
            for activity in ActivityKit.Activity<RecordingActivityAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    private nonisolated static func activity(id: String) -> ActivityKit.Activity<RecordingActivityAttributes>? {
        ActivityKit.Activity<RecordingActivityAttributes>.activities.first { $0.id == id }
    }

    static func contentState(for state: RecordingState, now: Date) -> RecordingActivityAttributes.ContentState {
        let progress = state.progressOrNull()
        let activeSeconds = state.activeTimeSeconds(now: .from(now))
        let status: RecordingActivityAttributes.ContentState.Status = switch onEnum(of: state) {
        case .recording(let recording) where recording.progress.pointCount > 0 && !recording.progress.isMoving: .autoPaused
        case .recording: .recording
        default: .paused
        }
        return RecordingActivityAttributes.ContentState(
            status: status,
            timerStart: state is RecordingStateRecording ? now.addingTimeInterval(-activeSeconds) : nil,
            activeSeconds: activeSeconds,
            distanceMeters: progress?.distanceMeters ?? 0,
            averageSpeedMetersPerSecond: state.averageSpeedMetersPerSecond(now: .from(now))?.doubleValue
        )
    }
}
