import SwiftUI

struct DesignPreviewRoot: View {
    @Environment(DesignPreviewNavigationModel.self) private var navigationModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        TabView(selection: tabSelection) {
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

            DesignPreviewSceneLaunchPage()
                .tabItem {
                    Label("Scene", systemImage: "mountain.2")
                }
                .tag(DesignPreviewTab.scene)
        }
        .tabViewStyle(.sidebarAdaptable)
        .accessibilityIdentifier("DesignPreview-rootTabView")
    }

    private var tabSelection: Binding<DesignPreviewTab> {
        Binding {
            navigationModel.selectedTab
        } set: { newTab in
            switch newTab {
            case .files, .settings:
                navigationModel.selectedTab = newTab
                navigationModel.rememberReturnRoute(from: newTab)
            case .scene:
                openSenseZone(from: navigationModel.selectedTab)
            }
        }
    }

    private func openSenseZone(from previousTab: DesignPreviewTab) {
        guard !navigationModel.isSceneTransitionInFlight else { return }

        let returnTab = previousTab.restorableTab ?? navigationModel.returnRoute.tab
        navigationModel.rememberReturnRoute(from: returnTab)
        navigationModel.isSceneTransitionInFlight = true
        navigationModel.selectedTab = returnTab
        openWindow(id: DesignPreviewNavigationModel.senseZoneVolumeID)
        dismissWindow(id: DesignPreviewNavigationModel.mainWindowID)
        navigationModel.isSceneTransitionInFlight = false
    }
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

private struct DesignPreviewSceneLaunchPage: View {
    var body: some View {
        Color.clear
            .accessibilityLabel("Opening SenseZone")
    }
}
