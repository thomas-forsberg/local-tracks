import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

@main
struct LocalTracksWidgets: WidgetBundle {
    var body: some Widget {
        RecordingLiveActivity()
    }
}

struct RecordingLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RecordingActivityAttributes.self) { context in
            LockScreenCard(attributes: context.attributes, state: context.state)
                .padding()
                .activityBackgroundTint(Theme.surface)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.attributes.sportName, systemImage: context.attributes.sportSymbol)
                        .font(.caption.weight(.semibold))
                }
                DynamicIslandExpandedRegion(.trailing) {
                    PauseButton(status: context.state.status)
                }
                DynamicIslandExpandedRegion(.center) {
                    RecordingTime(state: context.state).font(.title2.weight(.semibold))
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Text(LiveActivityFormat.distance(context.state.distanceMeters))
                        Spacer()
                        Text(LiveActivityFormat.speedOrPace(context.state.averageSpeedMetersPerSecond, showsPace: context.attributes.showsPace))
                    }
                    .font(.headline.monospacedDigit())
                }
            } compactLeading: {
                Image(systemName: context.attributes.sportSymbol)
            } compactTrailing: {
                RecordingTime(state: context.state)
                    .frame(maxWidth: 52)
            } minimal: {
                Image(systemName: context.attributes.sportSymbol)
            }
        }
    }
}

private struct LockScreenCard: View {
    let attributes: RecordingActivityAttributes
    let state: RecordingActivityAttributes.ContentState

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Label(statusText, systemImage: attributes.sportSymbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(state.status == .paused ? Theme.accent : Theme.inkSecondary)
                RecordingTime(state: state).font(.numbers(40, weight: .bold)).foregroundStyle(Theme.ink)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 4) {
                Text(LiveActivityFormat.distance(state.distanceMeters)).font(.numbers(26)).foregroundStyle(Theme.ink)
                Text(LiveActivityFormat.speedOrPace(state.averageSpeedMetersPerSecond, showsPace: attributes.showsPace))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .monospacedDigit()
            PauseButton(status: state.status)
        }
    }

    // Auto-pause only keeps standing still out of the moving time; it isn't something to show.
    private var statusText: String {
        state.status == .paused ? "Paused" : attributes.sportName
    }
}

// Counts up by itself while recording; frozen while paused.
private struct RecordingTime: View {
    let state: RecordingActivityAttributes.ContentState

    var body: some View {
        Group {
            if let start = state.timerStart {
                Text(timerInterval: start...Date.distantFuture, countsDown: false)
            } else {
                Text(LiveActivityFormat.clock(state.activeSeconds))
            }
        }
        .monospacedDigit()
        .multilineTextAlignment(.leading)
    }
}

private struct PauseButton: View {
    let status: RecordingActivityAttributes.ContentState.Status

    var body: some View {
        Button(intent: TogglePauseIntent()) {
            Image(systemName: status == .paused ? "play.fill" : "pause.fill")
                .font(.title3)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.circle)
        .tint(status == .paused ? Theme.forest : Theme.accent)
        .accessibilityLabel(status == .paused ? "Resume" : "Pause")
    }
}
