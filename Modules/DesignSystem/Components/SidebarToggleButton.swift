import SwiftUI

public struct SidebarToggleButton: View {
    @Binding private var isVisible: Bool
    private let accessibilityIdentifier: String

    public init(isVisible: Binding<Bool>, accessibilityIdentifier: String) {
        _isVisible = isVisible
        self.accessibilityIdentifier = accessibilityIdentifier
    }

    public var body: some View {
        Button {
            isVisible.toggle()
        } label: {
            GlassCircleIconLabel(
                systemName: isVisible ? "sidebar.leading" : "sidebar.left",
                accessibilityLabel: isVisible ? "Hide sidebar" : "Show sidebar",
                iconColor: .secondary,
                symbolContentTransition: .symbolEffect(.replace)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}

#Preview("Sidebar toggle") {
    @Previewable @State var isVisible = true
    return SidebarToggleButton(isVisible: $isVisible, accessibilityIdentifier: "preview-toggle")
        .padding(DesignTokens.Spacing.xxl)
}
