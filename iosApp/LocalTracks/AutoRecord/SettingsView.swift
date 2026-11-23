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
                        LabeledContent("Home", value: autoRecord.settings.home == nil ? String(localized: "Not set") : String(localized: "Set"))
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
                Section {
                    // iOS keeps a language per app; the app follows the phone's language until it's changed there.
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    } label: {
                        LabeledContent("Language", value: Locale.current.localizedString(forLanguageCode: Locale.current.language.languageCode?.identifier ?? "en")?.localizedCapitalized ?? "")
                    }
                    .foregroundStyle(Theme.ink)
                } footer: {
                    Text("Sporløs is in Norwegian and English and follows your phone's language. Change it for this app in iOS Settings.")
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
        case .atHome: String(localized: "At home")
        case .watching: String(localized: "Left home, checking how you're moving")
        case .autoRecording: String(localized: "Recording")
        case .arrivingHome: String(localized: "Recording the last bit home")
        case .manualRecording: String(localized: "Recording (started by you)")
        case .waitingForHome: String(localized: "Paused until you're home again")
        }
    }
}
