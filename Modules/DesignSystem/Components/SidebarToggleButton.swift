import SwiftUI

public struct SidebarToggleButton: View {
    @Binding private var isVisible: Bool
    private let accessibilityIdentifier: String

    public init(isVisible: Binding<Bool>, accessibilityIdentifier: String) {
        _isVisible = isVisible
        self.accessibilityIdentifier = accessibilityIdentifier
    }

    public var body: some View {
        GlassCircleIconButton(
            systemName: isVisible ? "sidebar.leading" : "sidebar.left",
            accessibilityLabel: isVisible ? "Hide sidebar" : "Show sidebar",
            action: { isVisible.toggle() },
            accessibilityIdentifier: accessibilityIdentifier
        )
    }
}

#if canImport(PreviewsMacros)
#Preview("Sidebar toggle") {
    @Previewable @State var isVisible = true
    SidebarToggleButton(isVisible: $isVisible, accessibilityIdentifier: "preview-toggle")
        .padding(DesignTokens.Spacing.xxl)
}
#endif
