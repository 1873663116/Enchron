import SwiftUI

#Preview("Home V1", windowStyle: .automatic) {
    HomeV1Page()
        .frame(
            width: EmptyPanelWindowContent<EmptyView>.defaultArtboardSize.width,
            height: EmptyPanelWindowContent<EmptyView>.defaultArtboardSize.height
        )
}

#Preview("Video Detail", windowStyle: .automatic) {
    DesignCompWindowPreviewStage(showsSidebar: true) {
        VideoDetailPage()
    }
}

#Preview("Player Control Panel", windowStyle: .automatic) {
    DesignCompWindowPreviewStage {
        PlayerControlPanelPage()
    }
}
