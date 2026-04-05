import SwiftUI

/// Vertical pill navigation for the main window's leading edge.
///
/// Contains 3 tab buttons (Browse / Recent / Settings) separated from
/// an independent Scene Selector circle button. Designed per R5–R8.
public struct NavigationOrnament: View {
    @Environment(AppModel.self) private var appModel
    @AccessibilityFocusState private var focusedTab: AppModel.NavigationTab?

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // MARK: - Tab Navigation Pill
            VStack(spacing: 12) {
                ForEach(AppModel.NavigationTab.allCases, id: \.self) { tab in
                    Button {
                        appModel.selectedTab = tab
                        focusedTab = tab
                    } label: {
                        Image(systemName: tab.iconName)
                            .font(.title2)
                            .foregroundStyle(
                                appModel.selectedTab == tab
                                    ? Color.enchronTertiary
                                    : Color.enchronOnSurfaceVariant
                            )
                            .frame(width: 60, height: 60)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .hoverEffect(.lift)
                    .accessibilityLabel(tab.label)
                    .accessibilityAddTraits(appModel.selectedTab == tab ? .isSelected : [])
                    .accessibilityFocused($focusedTab, equals: tab)
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 8)
            .enchronGlassControl()

            Spacer()
                .frame(height: 16)

            // MARK: - Scene Selector Button
            Button {
                appModel.showSceneSelector = true
            } label: {
                Image(systemName: "moon.stars")
                    .font(.title2)
                    .foregroundStyle(Color.enchronOnSurfaceVariant)
                    .frame(width: 60, height: 60)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .hoverEffect(.lift)
            .clipShape(.circle)
            .enchronGlassControl()
            .accessibilityLabel("Scene Selector")
        }
        .padding(.trailing, DesignTokens.Layout.ornamentGap)
    }
}

// MARK: - NavigationTab UI Mapping

extension AppModel.NavigationTab {
    /// SF Symbol icon name for each tab.
    var iconName: String {
        switch self {
        case .browse: "folder"
        case .recent: "clock"
        case .settings: "gearshape"
        }
    }

    /// Human-readable label for accessibility.
    var label: String {
        switch self {
        case .browse: "Browse"
        case .recent: "Recent"
        case .settings: "Settings"
        }
    }
}
