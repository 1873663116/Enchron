import SwiftUI

struct DesignPreviewRoot: View {
    @State private var selection: DesignPreviewTab = .files

    var body: some View {
        TabView(selection: $selection) {
            HomeFirstLaunchPage()
                .tabItem {
                    Label("Files", systemImage: "folder.fill")
                }
                .tag(DesignPreviewTab.files)

            DesignPreviewPlaceholderPage(title: "Settings")
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
                .tag(DesignPreviewTab.settings)

            CampScenePage()
                .tabItem {
                    Label("Scene", systemImage: "mountain.2")
                }
                .tag(DesignPreviewTab.scene)
        }
        .tabViewStyle(.sidebarAdaptable)
        .accessibilityIdentifier("DesignPreview-rootTabView")
    }
}

private enum DesignPreviewTab {
    case files
    case settings
    case scene
}

private struct DesignPreviewPlaceholderPage: View {
    let title: String

    var body: some View {
        Text(title)
            .font(DesignTokens.Typography.title)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityLabel(title)
    }
}
