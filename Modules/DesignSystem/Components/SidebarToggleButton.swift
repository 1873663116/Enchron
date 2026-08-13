import SwiftUI

/// Shows and hides a browsing sidebar. Built on `GlassCircleIconButton` at its default sizes so it
/// lines up with the nav capsule it stands beside, and so it inherits the silent hit target that a
/// bare `Button` wrapped around `GlassCircleIconLabel` does not have.
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
