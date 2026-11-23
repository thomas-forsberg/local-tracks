import Shared
import SwiftUI

struct RecordView: View {
    let controller: RecordingController
    let autoRecord: AutoRecordController
    @State private var showsSettings = false
    @State private var chosenSport: Sport = .cycling
    @State private var showsMap = false

    // While an activity is in progress its own sport wins over the picker.
    private var sport: Sport { controller.state.progressOrNull()?.sport ?? chosenSport }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if let unfinished = controller.unfinishedActivity {
                    UnfinishedActivityBanner(activity: unfinished, onResume: controller.resumeUnfinished, onSave: controller.finishUnfinished)
                }
                if controller.isStorageFailing {
                    Banner(systemImage: "externaldrive.badge.exclamationmark", tint: .red) {
                        Text("Can't save to the phone's storage. It may be full. Recording continues, and points are saved once there's space.")
                            .font(.callout)
                    }
                }
                if let problem = controller.locationProblem {
                    Banner(systemImage: "location.slash", tint: .orange) {
                        Text(problem.message).font(.callout)
                    }
                }

                if showsMap && isInProgress {
                    TrackMap(segments: controller.liveSegments, followsLatest: true)
                        .clipShape(.rect(cornerRadius: 16))
                    CompactStatsView(state: controller.state, sport: sport)
                } else {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        LiveStatsView(state: controller.state, sport: sport, now: context.date)
                    }
                    .padding(.top, 8)
                    Spacer(minLength: 0)
                }
                controls
            }
            .padding()
            .navigationTitle("Record")
            .sheet(isPresented: $showsSettings) { SettingsView(autoRecord: autoRecord) }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if isInProgress {
                        Button(showsMap ? "Show stats" : "Show map", systemImage: showsMap ? "gauge.with.dots.needle.33percent" : "map") {
                            showsMap.toggle()
                        }
                    } else {
                        Button("Settings", systemImage: "gearshape") { showsSettings = true }
                    }
                }
                if isInProgress {
                    ToolbarItem(placement: .topBarTrailing) {
                        RecordingDot(isRecording: controller.state is RecordingStateRecording)
                    }
                }
            }
        }
    }

    private var isInProgress: Bool {
        controller.state is RecordingStateRecording || controller.state is RecordingStatePaused
    }

    @ViewBuilder private var controls: some View {
        switch onEnum(of: controller.state) {
        case .idle, .finished:
            VStack(spacing: 16) {
                SportPicker(selection: $chosenSport)
                Button { controller.start(chosenSport) } label: {
                    Label("Start", systemImage: "play.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.extraLarge)
                .disabled(controller.unfinishedActivity != nil)
            }
        case .recording:
            HStack(spacing: 12) {
                Button(action: controller.pause) { Label("Pause", systemImage: "pause.fill").frame(maxWidth: .infinity) }
                    .buttonStyle(.bordered)
                Button(role: .destructive, action: controller.stop) { Label("Stop", systemImage: "stop.fill").frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent)
            }
            .controlSize(.extraLarge)
        case .paused:
            HStack(spacing: 12) {
                Button(action: controller.resume) { Label("Resume", systemImage: "play.fill").frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                Button(role: .destructive, action: controller.stop) { Label("Stop", systemImage: "stop.fill").frame(maxWidth: .infinity) }
                    .buttonStyle(.bordered)
            }
            .controlSize(.extraLarge)
        }
    }
}

private struct LiveStatsView: View {
    let state: RecordingState
    let sport: Sport
    let now: Date

    var body: some View {
        let progress = state.progressOrNull()
        let instant = KotlinInstant.from(now)
        let isRecording = state is RecordingStateRecording
        VStack(spacing: 28) {
            VStack(spacing: 0) {
                Text(((progress?.distanceMeters ?? 0) / 1000).formatted(.number.precision(.fractionLength(2))))
                    .font(.system(size: 80, weight: .bold, design: .rounded).monospacedDigit())
                    .contentTransition(.numericText())
                Text("km")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)

            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 20) {
                GridRow {
                    Stat(title: "Moving time", value: Formatters.clock(seconds: progress?.movingTimeSeconds ?? 0))
                    Stat(title: "Elapsed", value: Formatters.clock(seconds: state.elapsedSeconds(now: instant)))
                }
                GridRow {
                    SpeedStat(title: sport.currentSpeedTitle, metersPerSecond: isRecording ? progress?.currentSpeedMetersPerSecond?.doubleValue : nil, sport: sport)
                    SpeedStat(title: sport.averageSpeedTitle, metersPerSecond: state.averageSpeedMetersPerSecond(now: instant)?.doubleValue, sport: sport)
                }
                GridRow {
                    Stat(title: "Climb", value: Formatters.elevation(meters: progress?.elevationGain.meters ?? 0))
                    if sport.countsSteps {
                        Stat(title: "Steps", value: progress?.steps.map { Formatters.steps($0.intValue) } ?? "–")
                    } else {
                        Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// Under the live map: the numbers that matter most while moving.
private struct CompactStatsView: View {
    let state: RecordingState
    let sport: Sport

    var body: some View {
        let progress = state.progressOrNull()
        let speed = state is RecordingStateRecording ? progress?.currentSpeedMetersPerSecond?.doubleValue : nil
        HStack {
            Stat(title: "Distance", value: Formatters.distance(meters: progress?.distanceMeters ?? 0))
            Stat(title: "Moving time", value: Formatters.clock(seconds: progress?.movingTimeSeconds ?? 0))
            SpeedStat(title: sport.currentSpeedTitle, metersPerSecond: speed, sport: sport)
        }
        .dynamicTypeSize(...DynamicTypeSize.large)
    }
}

private struct Stat: View {
    let title: String
    let value: String
    var detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.subheadline).foregroundStyle(.secondary)
            Text(value)
                .font(.title.weight(.semibold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let detail {
                Text(detail).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

// Pace for running and hiking, with the speed in km/h underneath; speed alone for cycling.
private struct SpeedStat: View {
    let title: String
    let metersPerSecond: Double?
    let sport: Sport

    var body: some View {
        if sport.showsPace {
            Stat(title: title, value: Formatters.pace(metersPerSecond: metersPerSecond), detail: Formatters.speed(metersPerSecond: metersPerSecond))
        } else {
            Stat(title: title, value: Formatters.speed(metersPerSecond: metersPerSecond))
        }
    }
}

private struct SportPicker: View {
    @Binding var selection: Sport

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Sport.allCases, id: \.self) { sport in
                let isSelected = sport == selection
                Button { selection = sport } label: {
                    VStack(spacing: 4) {
                        Image(systemName: sport.systemImage).font(.title2)
                        Text(sport.title).font(.footnote.weight(.medium))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .foregroundStyle(isSelected ? Color.white : Color.primary)
                    .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.12), in: .rect(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }
}

// Shows at a glance that a recording is running: a red dot that slowly fades in and out like a
// recording light, still and dimmed while paused, and still with Reduce Motion.
private struct RecordingDot: View {
    let isRecording: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if isRecording && !reduceMotion {
                dot.phaseAnimator([1.0, 0.25]) { view, opacity in
                    view.opacity(opacity)
                } animation: { _ in
                    .easeInOut(duration: 1)
                }
            } else {
                dot.opacity(isRecording ? 1 : 0.35)
            }
        }
        .padding(.horizontal, 6)
        .accessibilityElement()
        .accessibilityLabel(isRecording ? "Recording" : "Paused")
    }

    private var dot: some View {
        Circle().fill(.red).frame(width: 12, height: 12)
    }
}

private struct Banner<Content: View>: View {
    let systemImage: String
    let tint: Color
    @ViewBuilder let content: Content

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage).font(.title3).foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 8) { content }
            Spacer(minLength: 0)
        }
        .padding()
        .background(tint.opacity(0.12), in: .rect(cornerRadius: 14))
    }
}

private struct UnfinishedActivityBanner: View {
    let activity: ActivitySummary
    let onResume: () -> Void
    let onSave: () -> Void

    var body: some View {
        Banner(systemImage: "exclamationmark.arrow.circlepath", tint: .yellow) {
            Text("Unfinished \(activity.sport.title.lowercased()) activity").font(.headline)
            Text("Started \(activity.startedAt.date.formatted(date: .abbreviated, time: .shortened)), \(Formatters.distance(meters: activity.totals.distanceMeters)) recorded.")
                .font(.callout)
            HStack {
                Button("Resume", action: onResume).buttonStyle(.borderedProminent)
                Button("Save as is", action: onSave).buttonStyle(.bordered)
            }
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
