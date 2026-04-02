import SwiftUI

public struct SettingsView: View {
    @State private var resumePolicy: PersistenceDomain.ResumePolicy = .askEveryTime
    private let preferencesStore: PreferencesStoring

    public init(preferencesStore: PreferencesStoring = UserDefaultsStore()) {
        self.preferencesStore = preferencesStore
    }

    public var body: some View {
        List {
            Section("Playback") {
                Picker("Resume Behavior", selection: $resumePolicy) {
                    Text("Ask Every Time").tag(PersistenceDomain.ResumePolicy.askEveryTime)
                    Text("Always Resume").tag(PersistenceDomain.ResumePolicy.alwaysResume)
                    Text("Always Start Over").tag(PersistenceDomain.ResumePolicy.alwaysStartFromBeginning)
                }
            }

            Section("Immersive Space") {
                ToggleImmersiveSpaceButton()
            }

            Section("About") {
                LabeledContent("Version", value: "0.1")
                LabeledContent("Build", value: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—")
            }
        }
        .navigationTitle("Settings")
        .onAppear {
            resumePolicy = preferencesStore.loadPreferences().resumePolicy
        }
        .onChange(of: resumePolicy) { _, newValue in
            var prefs = preferencesStore.loadPreferences()
            prefs.resumePolicy = newValue
            preferencesStore.savePreferences(prefs)
        }
    }
}
