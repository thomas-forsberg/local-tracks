import Shared
import SwiftUI

// Basic record screen to try recording end to end; step 4 turns it into the real one.
struct RecordView: View {
    let controller: RecordingController
    @State private var sport: Sport = .cycling

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                if let unfinished = controller.unfinishedActivity {
                    UnfinishedActivityBanner(
                        activity: unfinished,
                        onResume: controller.resumeUnfinished,
                        onSave: controller.finishUnfinished
                    )
                }

                TimelineView(.periodic(from: .now, by: 1)) { context in
                    LiveStatsView(state: controller.state, now: context.date)
                }

                if let problem = controller.locationProblem {
                    Label(problem.message, systemImage: "location.slash")
                        .foregroundStyle(.orange)
                        .font(.callout)
                }

                Spacer()
                controls
            }
            .padding()
            .navigationTitle("Record")
        }
    }

    @ViewBuilder private var controls: some View {
        switch onEnum(of: controller.state) {
        case .idle, .finished:
            Picker("Sport", selection: $sport) {
                ForEach(Sport.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            Button("Start") { controller.start(sport) }
                .buttonStyle(.borderedProminent)
                .disabled(controller.unfinishedActivity != nil)
        case .recording:
            HStack {
                Button("Pause", action: controller.pause).buttonStyle(.bordered)
                Button("Stop", role: .destructive, action: controller.stop).buttonStyle(.borderedProminent)
            }
        case .paused:
            HStack {
                Button("Resume", action: controller.resume).buttonStyle(.borderedProminent)
                Button("Stop", role: .destructive, action: controller.stop).buttonStyle(.bordered)
            }
        }
    }
}

private struct LiveStatsView: View {
    let state: RecordingState
    let now: Date

    var body: some View {
        let progress = state.progressOrNull()
        let instant = KotlinInstant.from(now)
        Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
            GridRow { Text("Status").foregroundStyle(.secondary); Text(state.title) }
            GridRow { Text("Distance").foregroundStyle(.secondary); Text(Formatters.distance(meters: progress?.distanceMeters ?? 0)) }
            GridRow { Text("Time").foregroundStyle(.secondary); Text(Formatters.duration(seconds: state.activeTimeSeconds(now: instant))) }
            GridRow { Text("Avg speed").foregroundStyle(.secondary); Text(Formatters.speed(metersPerSecond: state.averageSpeedMetersPerSecond(now: instant)?.doubleValue)) }
            GridRow { Text("Climb").foregroundStyle(.secondary); Text(Formatters.elevation(meters: progress?.elevationGain.meters ?? 0)) }
            GridRow { Text("Points").foregroundStyle(.secondary); Text("\(progress?.pointCount ?? 0)") }
        }
        .font(.title3.monospacedDigit())
    }
}

private struct UnfinishedActivityBanner: View {
    let activity: ActivitySummary
    let onResume: () -> Void
    let onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Unfinished \(activity.sport.title.lowercased()) activity")
                .font(.headline)
            Text("Started \(activity.startedAt.date.formatted(date: .abbreviated, time: .shortened)), \(Formatters.distance(meters: activity.totals.distanceMeters)) recorded.")
                .font(.callout)
            HStack {
                Button("Resume", action: onResume).buttonStyle(.borderedProminent)
                Button("Save as is", action: onSave).buttonStyle(.bordered)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.yellow.opacity(0.15), in: .rect(cornerRadius: 12))
    }
}

extension RecordingState {
    var title: String {
        switch onEnum(of: self) {
        case .idle: "Ready"
        case .recording: "Recording"
        case .paused: "Paused"
        case .finished: "Saved"
        }
    }
}

extension LocationProblem {
    var message: String {
        switch self {
        case .permissionDenied: "Location access is off. Turn it on in Settings to record."
        case .approximateLocationOnly: "Precise Location is off. Turn it on in Settings for accurate tracks."
        case .unavailable: "Waiting for GPS…"
        }
    }
}
