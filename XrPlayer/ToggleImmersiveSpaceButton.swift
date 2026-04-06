//
//  ToggleImmersiveSpaceButton.swift
//  XrPlayer
//
//  Created by 熊志鹏 on 2026/3/3.
//

import SwiftUI

public struct ToggleImmersiveSpaceButton: View {

    public enum Style {
        /// Full-width text button (default, used in SceneSelectorView).
        case standard
        /// Icon-only button suitable for toolbar placement.
        case compact
    }

    private let style: Style

    @Environment(AppModel.self) private var appModel

    public init(style: Style = .standard) {
        self.style = style
    }

    public var body: some View {
        Button {
            // §5.9a: route open/dismiss through unified AppModel request,
            // which is processed by the canonical handler in MainView.
            switch appModel.immersiveSpaceState {
            case .open:
                appModel.requestDismissImmersiveSpace()
            case .closed:
                appModel.requestImmersiveSpace()
            case .inTransition:
                // Button is disabled in this state; guard is a safety net.
                break
            }
        } label: {
            switch style {
            case .standard:
                Text(appModel.immersiveSpaceState == .open ? "Hide Immersive Space" : "Show Immersive Space")
            case .compact:
                Image(systemName: appModel.immersiveSpaceState == .open
                      ? "visionpro.fill"
                      : "visionpro")
            }
        }
        .disabled(appModel.immersiveSpaceState == .inTransition)
        .animation(.none, value: 0)
        .fontWeight(.semibold)
    }
}
