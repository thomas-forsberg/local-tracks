import SwiftUI

struct RootView: View {
    let environment: AppEnvironment
    @State private var tab = AppTab.record

    var body: some View {
        TabView(selection: $tab) {
            Tab("Record", systemImage: "record.circle", value: .record) {
                RecordView(controller: environment.recording, autoRecord: environment.autoRecord, onShowActivities: { tab = .activities })
            }
            Tab("Activities", systemImage: "list.bullet", value: .activities) {
                ActivitiesView(viewModel: environment.activities)
            }
            Tab("Stats", systemImage: "chart.bar", value: .stats) {
                StatsView(viewModel: environment.stats)
            }
            Tab("Maps", systemImage: "map", value: .maps) {
                MapsView(library: environment.maps)
            }
        }
        // Every map in the app shows the downloaded regions.
        .environment(environment.maps)
        .tint(Theme.accent)
    }
}

enum AppTab: Hashable {
    case record, activities, stats, maps
}
