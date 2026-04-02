import SwiftUI

public struct AppTabView: View {
    @Environment(AppModel.self) private var appModel

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
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if !appModel.isPlaying {
                    ToggleImmersiveSpaceButton(style: .compact)
                        .help(appModel.immersiveSpaceState == .open
                              ? "Hide Immersive Space"
                              : "Show Immersive Space")
                }
            }
        }
    }
}
