import SwiftUI

#Preview("App First Launch", windowStyle: .automatic) {
    DesignPreviewRootPreviewHost()
}

#Preview("Window Playback", windowStyle: .plain) {
    WindowPlaybackPreviewHost()
}

#Preview(
    "SenseZone Volume",
    windowStyle: .volumetric,
    traits: .fixedLayout(
        width: DesignTokens.SceneCarousel.stageWidth,
        height: DesignTokens.SceneCarousel.stageHeight,
        depth: DesignTokens.SceneCarousel.stageDepth
    )
) {
    SenseZoneVolumePreviewHost()
}

private struct DesignPreviewRootPreviewHost: View {
    @State private var navigationModel = DesignPreviewNavigationModel()

    var body: some View {
        DesignPreviewRoot()
            .environment(navigationModel)
    }
}

private struct WindowPlaybackPreviewHost: View {
    @State private var navigationModel = DesignPreviewNavigationModel()

    var body: some View {
        WindowPlaybackPage()
            .environment(navigationModel)
    }
}

private struct SenseZoneVolumePreviewHost: View {
    @State private var navigationModel = DesignPreviewNavigationModel()

    var body: some View {
        SenseZoneVolumeRoot()
            .environment(navigationModel)
    }
}
