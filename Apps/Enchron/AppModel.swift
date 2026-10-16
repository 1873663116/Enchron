import SwiftUI
import Observation

@MainActor
@Observable
public final class AppModel {
    public enum NavigationTab: String, CaseIterable {
        case files, emby, plex, jellyfin, streaming, settings, environment

        func contentDestination(in visibility: MediaLibraryTabVisibility) -> NavigationTab {
            switch self {
            case .files, .streaming, .settings, .environment:
                self
            case .emby:
                visibility.emby ? self : .files
            case .plex:
                visibility.plex ? self : .files
            case .jellyfin:
                visibility.jellyfin ? self : .files
            }
        }
    }
    public var isEnvironmentHomeCompact = false
    public var selectedTab: NavigationTab = .files
}
