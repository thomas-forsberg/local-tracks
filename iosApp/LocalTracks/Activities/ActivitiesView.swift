import Shared
import SwiftUI

struct ActivitiesView: View {
    let viewModel: ActivitiesViewModel
    @State private var pendingDeletion: ActivitySummary?
    @State private var toggled: Set<ActivityGroup.Period> = []

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Activities")
                .navigationDestination(for: ActivitySummary.self) { activity in
                    ActivityDetailView(viewModel: viewModel.detail(for: activity))
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
            List {
                ForEach(ActivityGroup.grouping(activities)) { group in
                    let expanded = isExpanded(group)
                    GroupHeader(group: group, isExpanded: expanded) {
                        withAnimation { toggled.formSymmetricDifference([group.period]) }
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 14, leading: 16, bottom: 4, trailing: 16))
                    .opacity(pendingDeletion == nil ? 1 : 0)
                    .animation(.easeInOut(duration: 0.2), value: pendingDeletion?.id)
                    if expanded {
                        ForEach(group.activities, id: \.id) { activity in
                            row(activity)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .themedList()
            // An alert, not a confirmation dialog: that is a popover anchored to the row, and it closed
            // as soon as the row slid back after the swipe.
            .alert(
                pendingDeletion?.sport.deletionTitle ?? "",
                isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }),
                presenting: pendingDeletion
            ) { activity in
                Button("Delete", role: .destructive) { viewModel.delete(activity) }
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text("This can't be undone. Your activities only exist on this phone.")
            }
        }
    }

    // Groups whose expanded state the user flipped from how they start.
    private func isExpanded(_ group: ActivityGroup) -> Bool {
        group.startsExpanded != toggled.contains(group.period)
    }

    private func row(_ activity: ActivitySummary) -> some View {
        ActivityRow(activity: activity, preview: viewModel.routePreview(for: activity))
            // The link fills the card but draws nothing, so rows don't get list chevrons.
            .background(NavigationLink(value: activity) { EmptyView() }.opacity(0))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            .swipeActions {
                Button("Delete", systemImage: "trash", role: .destructive) { pendingDeletion = activity }
            }
            // While deleting, only the activity being deleted stays visible behind the alert.
            .opacity(pendingDeletion == nil || pendingDeletion?.id == activity.id ? 1 : 0)
            .animation(.easeInOut(duration: 0.2), value: pendingDeletion?.id)
    }
}

// Tapping it shows or hides the group's activities.
private struct GroupHeader: View {
    let group: ActivityGroup
    let isExpanded: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(group.title())
                    .font(.numbers(24, weight: .bold, relativeTo: .title3))
                Spacer()
                Text("\(String(localized: "\(group.activities.count) activities")) · \(Formatters.distance(meters: group.distanceMeters))")
                    .font(.subheadline)
                    .foregroundStyle(Theme.inkSecondary)
                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.inkSecondary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
            }
            .foregroundStyle(Theme.ink)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityValue(isExpanded ? String(localized: "Expanded") : String(localized: "Collapsed"))
    }
}

private extension Sport {
    // Whole sentences per sport: languages inflect the sport differently.
    var deletionTitle: String {
        switch self {
        case .cycling: String(localized: "Delete this ride?")
        case .running: String(localized: "Delete this run?")
        case .hiking: String(localized: "Delete this hike?")
        }
    }
}

private struct ActivityRow: View {
    let activity: ActivitySummary
    let preview: RoutePreview?

    var body: some View {
        HStack(spacing: 14) {
            RouteThumbnail(preview: preview, sport: activity.sport)
                .frame(width: 84, height: 84)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(activity.sport.title)
                        .font(.headline)
                        .foregroundStyle(activity.sport.color)
                    if activity.suspectedCar {
                        Label("Car ride?", systemImage: "car.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.orange)
                    }
                }
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
        .accessibilityIdentifier("activity")
    }
}
