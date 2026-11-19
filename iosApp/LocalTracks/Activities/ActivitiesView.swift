import Shared
import SwiftUI

struct ActivitiesView: View {
    let viewModel: ActivitiesViewModel
    @State private var pendingDeletion: ActivitySummary?

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Activities")
                .navigationDestination(for: ActivitySummary.self) { activity in
                    ActivityDetailView(viewModel: viewModel.detail(for: activity))
                }
                .confirmationDialog(
                    deletionTitle,
                    isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }),
                    titleVisibility: .visible,
                    presenting: pendingDeletion
                ) { activity in
                    Button("Delete", role: .destructive) { viewModel.delete(activity) }
                } message: { _ in
                    Text("This can't be undone. Your activities only exist on this phone.")
                }
        }
        .task { await viewModel.observe() }
    }

    @ViewBuilder private var content: some View {
        switch viewModel.activities {
        case nil:
            ProgressView()
        case let activities? where activities.isEmpty:
            ContentUnavailableView("No activities yet", systemImage: "figure.walk", description: Text("Recorded activities show up here."))
        case let activities?:
            List(activities, id: \.id) { activity in
                NavigationLink(value: activity) {
                    ActivityRow(activity: activity)
                }
                    .swipeActions {
                        Button("Delete", systemImage: "trash", role: .destructive) { pendingDeletion = activity }
                    }
            }
        }
    }

    private var deletionTitle: String {
        guard let activity = pendingDeletion else { return "" }
        return "Delete this \(activity.sport.title.lowercased()) activity?"
    }
}

private struct ActivityRow: View {
    let activity: ActivitySummary

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: activity.sport.systemImage)
                .font(.title2)
                .frame(width: 36)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 4) {
                Text(activity.sport.title)
                    .font(.headline)
                Text(activity.startedAt.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text([
                    Formatters.distance(meters: activity.totals.distanceMeters),
                    Formatters.shortDuration(seconds: activity.totals.movingTimeSeconds),
                    "↑ " + Formatters.elevation(meters: activity.totals.elevationGainMeters),
                ].joined(separator: " · "))
                    .font(.subheadline.monospacedDigit())
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}
