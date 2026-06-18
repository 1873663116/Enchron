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
        // TEMP(simulator 验证 ornament 旋转/window bar): 临时把启动窗口设为播放窗口
        // 状态 B。验证后还原为 DesignPreviewRoot()。
        WindowGroup(id: DesignPreviewNavigationModel.mainWindowID) {
            WindowPlaybackPage(
                initialChromeVisible: true,
                initialSettingsPanelPresented: true,
                initialTimelineExpanded: true
            )
            .environment(navigationModel)
        }
        .windowStyle(.plain)

        WindowGroup(id: DesignPreviewNavigationModel.senseZoneVolumeID) {
            SenseZoneVolumeRoot()
                .environment(navigationModel)
        }
        .windowStyle(.volumetric)
        .defaultSize(
            width: DesignTokens.EnvironmentCarousel.volumeWidthMeters,
            height: DesignTokens.EnvironmentCarousel.volumeHeightMeters,
            depth: DesignTokens.EnvironmentCarousel.volumeDepthMeters,
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
