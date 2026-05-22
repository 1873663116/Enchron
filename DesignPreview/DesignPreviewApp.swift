//
//  DesignPreviewApp.swift
//  DesignPreview
//
//  Created by 熊志鹏 on 2026/4/7.
//

import SwiftUI

@main
struct DesignPreviewApp: App {
    var body: some Scene {
        WindowGroup {
            DesignPreviewRoot()
        }

        WindowGroup("Empty Panel", id: "designComps-emptyPanel") {
            EmptyPanelWindowContent()
        }
        .defaultSize(width: 1920, height: 1080)
        .windowResizability(.contentSize)
    }
}
