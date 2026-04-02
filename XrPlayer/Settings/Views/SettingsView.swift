import SwiftUI

public struct SettingsView: View {
    @State private var autoResumeEnabled = true

    public init() {}

    public var body: some View {
        List {
            Section("Playback") {
                Toggle("Auto Resume", isOn: $autoResumeEnabled)
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
    }
}
