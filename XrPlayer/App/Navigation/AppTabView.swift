import SwiftUI

public struct AppTabView: View {
    public init() {}
    
    public var body: some View {
        TabView {
            Tab("Files", systemImage: "folder") {
                FileBrowserView()
            }
            
            Tab("Scenes", systemImage: "moon.stars") {
                SceneSelectorView()
            }
            
            Tab("Settings", systemImage: "gearshape") {
                SettingsView()
            }
        }
        .tabViewStyle(.sidebarAdaptable)
    }
}
