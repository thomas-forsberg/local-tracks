import SwiftUI

struct RootView: View {
    let environment: AppEnvironment

    var body: some View {
        TabView {
            Tab("Record", systemImage: "record.circle") {
                RecordView(controller: environment.recording)
            }
            Tab("Activities", systemImage: "list.bullet") {
                ActivitiesView(viewModel: environment.activities)
            }
            Tab("Stats", systemImage: "chart.bar") {
                StatsView(viewModel: environment.stats)
            }
            Tab("Maps", systemImage: "map") {
                MapsView(library: environment.maps)
            }
        }
    }
}
