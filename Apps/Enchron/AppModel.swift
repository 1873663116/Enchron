import SwiftUI
import Observation

@MainActor
@Observable
public final class AppModel {
    public enum NavigationTab: String, CaseIterable {
        case files, emby, plex, jellyfin, settings, environment

        var isContentDestination: Bool {
            self != .environment
        }

        func contentDestination(in visibility: MediaLibraryTabVisibility) -> NavigationTab {
            switch self {
            case .files, .settings:
                self
            case .emby:
                visibility.emby ? self : .files
            case .plex:
                visibility.plex ? self : .files
            case .jellyfin:
                visibility.jellyfin ? self : .files
            case .environment:
                .files
            }
        }
    }
    public var selectedTab: NavigationTab = .files
}
