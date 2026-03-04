import SwiftUI

public struct SettingsView: View {
    @State private var autoResumeEnabled = true

    public init() {}
    
    public var body: some View {
        List {
            Section("General") {
                Toggle("Auto Resume", isOn: $autoResumeEnabled)
            }
            
            Section("About") {
                Text("Version 0.1")
            }
        }
        .navigationTitle("Settings")
    }
}
