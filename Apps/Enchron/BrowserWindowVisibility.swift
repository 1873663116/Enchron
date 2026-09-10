import Playback
import SwiftUI

struct BrowserWindowVisibility {
    let hidesBrowser: Bool

    init(
        window: SpatialPlatformWindowIdentity,
        playbackResidency: PlaybackResidency
    ) {
        hidesBrowser = SpatialPlatformBrowserWindowVisibilityPolicy.hidesBrowser(
            window: window,
            playbackResidency: playbackResidency
        )
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
            .allowsHitTesting(visibility.hidesBrowser == false)
            .accessibilityHidden(visibility.hidesBrowser)
    }

    func browserTabBarVisibility(
        _ visibility: BrowserWindowVisibility
    ) -> some View {
        toolbarVisibility(visibility.systemOverlays, for: .tabBar)
    }
}
