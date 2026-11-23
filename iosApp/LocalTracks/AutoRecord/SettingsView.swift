import Shared
import SwiftUI

struct SettingsView: View {
    let autoRecord: AutoRecordController
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var isEnabling = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Record when I leave home", isOn: Binding(
                        get: { autoRecord.isEnabled },
                        set: { on in
                            if on {
                                Task {
                                    isEnabling = true
                                    await autoRecord.enable()
                                    isEnabling = false
                                }
                            } else {
                                autoRecord.disable()
                            }
                        }
                    ))
                    .disabled(autoRecord.settings.home == nil || isEnabling)

                    NavigationLink {
                        HomePickerView(autoRecord: autoRecord)
                    } label: {
                        LabeledContent("Home", value: autoRecord.settings.home == nil ? "Not set" : "Set")
                    }

                    if autoRecord.isEnabled {
                        LabeledContent("Now", value: autoRecord.phase.description)
                    }
                    if autoRecord.needsAlwaysLocation {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Location access must be set to Always for this to work.", systemImage: "location.slash")
                                .foregroundStyle(.orange)
                            Button("Open Settings") {
                                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                            }
                        }
                    }
                } header: {
                    Text("Auto-record")
                } footer: {
                    Text("When you leave home on foot or by bike, recording starts by itself and stops when you're back. Leaving by car doesn't start anything until you're home again. Short trips are deleted. Your home is stored only on this phone.")
                }
            }
            .themedList()
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

extension AutoRecordPhase {
    var description: String {
        switch self {
        case .atHome: "At home"
        case .watching: "Left home, checking how you're moving"
        case .autoRecording: "Recording"
        case .arrivingHome: "Recording the last bit home"
        case .manualRecording: "Recording (started by you)"
        case .waitingForHome: "Paused until you're home again"
        }
    }
}
