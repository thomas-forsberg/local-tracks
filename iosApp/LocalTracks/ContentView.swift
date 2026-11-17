import Shared
import SwiftUI

struct ContentView: View {
    // Placeholder until phase 1; proves the Swift → Kotlin call path end to end.
    private let osloToBergenKm: Double = {
        let oslo = TrackPoint(latitude: 59.9111, longitude: 10.7528, elevationMeters: nil, time: nil)
        let bergen = TrackPoint(latitude: 60.3913, longitude: 5.3221, elevationMeters: nil, time: nil)
        return DistanceKt.distanceMeters(from: oslo, to: bergen) / 1000
    }()

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "figure.outdoor.cycle")
                .font(.system(size: 48))
            Text("Local Tracks")
                .font(.largeTitle.bold())
            Text("Oslo → Bergen: \(osloToBergenKm, format: .number.precision(.fractionLength(1))) km")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
