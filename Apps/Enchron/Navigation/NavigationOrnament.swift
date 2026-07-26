import DesignSystem
import PlaybackFeature
import SwiftUI

/// Vertical pill navigation for the main window's leading edge.
///
/// Three tab buttons (Files / Settings / Environments). Files and Settings render
/// content in the main window; Environments opens its own destination (volume) and
/// does not park the main window on a blank tab (LNCH-03).
public struct NavigationOrnament: View {
    @Environment(AppModel.self) private var appModel
    #if os(visionOS)
    @Environment(PlaybackRuntime.self) private var playbackRuntime
    #endif
    @AccessibilityFocusState private var focusedTab: AppModel.NavigationTab?

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // MARK: - Tab Navigation Pill
            VStack(spacing: 12) {
                ForEach(AppModel.NavigationTab.allCases, id: \.self) { tab in
                    Button {
                        if tab.isContentDestination {
                            appModel.selectedTab = tab
                            focusedTab = tab
                        } else {
                            #if os(visionOS)
                            // Environments opens its own destination — the SenseZone
                            // volume with the polished EnvironmentCardCarousel — without
                            // parking the main window on a blank tab (LNCH-03 / ENV-13).
                            try? appModel.requestEnvironmentCard(
                                mediaSessionID: playbackRuntime.activeSessionID,
                                wasPlaying: playbackRuntime.productLifecycle == .playing
                            )
                            #else
                            appModel.selectedTab = .environment
                            focusedTab = .environment
                            #endif
                        }
                    } label: {
                        Image(systemName: tab.iconName)
                            .font(.title2)
                            .foregroundStyle(
                                appModel.selectedTab == tab
                                    ? DesignTokens.Theme.tertiary
                                    : DesignTokens.Theme.onSurfaceVariant
                            )
                            .frame(width: 60, height: 60)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .enchronHoverEffect(.lift)
                    .accessibilityIdentifier("Navigation-Ornament-tab-\(tab.rawValue)")
                    .accessibilityLabel(tab.label)
                    .accessibilityAddTraits(appModel.selectedTab == tab ? .isSelected : [])
                    .accessibilityFocused($focusedTab, equals: tab)
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 8)
            .enchronGlassControl()
        }
        .padding(.trailing, DesignTokens.Layout.ornamentGap)
    }
}

// MARK: - NavigationTab UI Mapping

extension AppModel.NavigationTab {
    /// SF Symbol icon name for each tab.
    var iconName: String {
        switch self {
        case .files: "folder"
        case .settings: "gearshape"
        case .environment: "mountain.2"
        }
    }

    /// Human-readable label for accessibility.
    var label: String {
        switch self {
        case .files: "Files"
        case .settings: "Settings"
        case .environment: "Environments"
        }
    }
}
