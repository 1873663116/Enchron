import DesignSystem
import Playback
import SwiftUI

struct BrowserWindowVisibility {
    let hidesBrowser: Bool
    let isCompact: Bool

    init(
        window: SpatialPlatformWindowIdentity,
        playbackResidency: PlaybackResidency,
        isCompact: Bool = false
    ) {
        self.isCompact = isCompact
        hidesBrowser = SpatialPlatformBrowserWindowVisibilityPolicy.hidesBrowser(
            window: window,
            playbackResidency: playbackResidency
        )
    }

    var tabBarVisibility: Visibility {
        isCompact ? .hidden : systemOverlays
    }

    var systemOverlays: Visibility {
        hidesBrowser ? .hidden : .automatic
    }
}

extension View {
    func browserWindowContentVisibility(
        _ visibility: BrowserWindowVisibility
    ) -> some View {
        opacity(visibility.hidesBrowser ? 0 : 1)
            .environment(\.searchInputIsAvailable, !visibility.hidesBrowser)
            .allowsHitTesting(visibility.hidesBrowser == false)
            .accessibilityHidden(visibility.hidesBrowser)
    }

    func browserTabBarVisibility(
        _ visibility: BrowserWindowVisibility
    ) -> some View {
        toolbarVisibility(visibility.tabBarVisibility, for: .tabBar)
    }
}
