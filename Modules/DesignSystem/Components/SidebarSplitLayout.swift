import SwiftUI

public struct SidebarSplitLayout<Sidebar: View, Content: View>: View {
    private let sidebarIsVisible: Bool
    private let sidebar: Sidebar
    private let content: Content

    public init(
        sidebarIsVisible: Bool,
        @ViewBuilder sidebar: () -> Sidebar,
        @ViewBuilder content: () -> Content
    ) {
        self.sidebarIsVisible = sidebarIsVisible
        self.sidebar = sidebar()
        self.content = content()
    }

    public var body: some View {
        GeometryReader { proxy in
            let sidebarWidth = DesignTokens.SourceSidebar.width
            let contentWidth = max(0, proxy.size.width - (sidebarIsVisible ? sidebarWidth : 0))
            ZStack(alignment: .leading) {
                content
                    .frame(width: contentWidth, height: proxy.size.height)
                    .offset(x: sidebarIsVisible ? sidebarWidth : 0)
                if sidebarIsVisible {
                    sidebar
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }
            }
            .animation(DesignTokens.AnimationToken.controlsTransition, value: sidebarIsVisible)
        }
    }
}
