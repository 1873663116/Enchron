import SwiftUI

public struct SettingsView: View {
    public init() {}
    
    public var body: some View {
        List {
            Section("General") {
                Toggle("Auto Resume", isOn: .constant(true))
            }
            
            Section("About") {
                Text("Version 0.1")
            }
        }
        .navigationTitle("Settings")
    }
}
