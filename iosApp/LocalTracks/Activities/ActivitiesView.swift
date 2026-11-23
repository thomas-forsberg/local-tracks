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
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity).background(Theme.background)
        case let activities? where activities.isEmpty:
            ContentUnavailableView("No activities yet", systemImage: "figure.walk", description: Text("Recorded activities show up here."))
                .background(Theme.background)
        case let activities?:
            List(activities, id: \.id) { activity in
                ActivityRow(activity: activity)
                    // The link fills the card but draws nothing, so rows don't get list chevrons.
                    .background(NavigationLink(value: activity) { EmptyView() }.opacity(0))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    .swipeActions {
                        Button("Delete", systemImage: "trash", role: .destructive) { pendingDeletion = activity }
                    }
            }
            .listStyle(.plain)
            .themedList()
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
        HStack(spacing: 14) {
            Image(systemName: activity.sport.systemImage)
                .font(.title)
                .foregroundStyle(activity.sport.color)
                .frame(width: 64, height: 64)
                .background(activity.sport.color.opacity(0.14), in: .rect(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 2) {
                Text(activity.sport.title)
                    .font(.headline)
                    .foregroundStyle(activity.sport.color)
                Text(activity.startedAt.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.subheadline)
                    .foregroundStyle(Theme.inkSecondary)
                HStack(spacing: 14) {
                    Text(Formatters.distance(meters: activity.totals.distanceMeters))
                    Text(Formatters.compactDuration(seconds: activity.totals.movingTimeSeconds))
                    Text("↑ " + Formatters.elevation(meters: activity.totals.elevationGainMeters)).foregroundStyle(Theme.climb)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .font(.numbers(22, relativeTo: .title3))
                .foregroundStyle(Theme.ink)
                .padding(.top, 4)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .card()
        .accessibilityElement(children: .combine)
    }
}
