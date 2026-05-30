//
//  DesignPreviewApp.swift
//  DesignPreview
//
//  Created by 熊志鹏 on 2026/4/7.
//

import SwiftUI

@main
struct DesignPreviewApp: App {
    @State private var navigationModel = DesignPreviewNavigationModel()

    var body: some Scene {
        WindowGroup(id: DesignPreviewNavigationModel.mainWindowID) {
            DesignPreviewRoot()
                .environment(navigationModel)
        }
        .windowStyle(.plain)

        WindowGroup(id: DesignPreviewNavigationModel.senseZoneVolumeID) {
            SenseZoneVolumeRoot()
                .environment(navigationModel)
        }
        .windowStyle(.volumetric)
        .defaultSize(
            width: DesignTokens.SceneCarousel.volumeWidthMeters,
            height: DesignTokens.SceneCarousel.volumeHeightMeters,
            depth: DesignTokens.SceneCarousel.volumeDepthMeters,
            in: .meters
        )
        .windowResizability(.contentSize)

        WindowGroup(id: DesignPreviewNavigationModel.windowPlaybackWindowID) {
            WindowPlaybackPage()
                .environment(navigationModel)
        }
        .windowStyle(.plain)
        .defaultSize(
            width: WindowPlaybackPage.idealContentSize.width,
            height: WindowPlaybackPage.idealContentSize.height
        )
        .windowResizability(.contentSize)
    }
}
