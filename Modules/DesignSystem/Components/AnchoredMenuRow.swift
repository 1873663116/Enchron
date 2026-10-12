import SwiftUI

public struct AnchoredMenuButtonStyle: ButtonStyle {
    private let isSelected: Bool

    public init(isSelected: Bool = false) { self.isSelected = isSelected }

    public func makeBody(configuration: Configuration) -> some View {
        let inset = DesignTokens.Menu.rowVisualInset
        let vertical = DesignTokens.Menu.rowVerticalInset
        let insets = EdgeInsets(top: vertical, leading: inset, bottom: vertical, trailing: inset)
        return configuration.label
            .font(DesignTokens.Typography.selectionHeader)
            .labelStyle(.titleAndIcon)
            .frame(maxWidth: .infinity, minHeight: DesignTokens.Menu.rowVisualHeight, alignment: .leading)
            .padding(.horizontal, DesignTokens.Spacing.sm)
            .background {
                if isSelected { DesignTokens.ShapeToken.menuRow.fill(DesignTokens.Surface.selected) }
            }
            .enchronHoverTarget(visual: DesignTokens.ShapeToken.menuRow,
                                interaction: DesignTokens.ShapeToken.menuRow,
                                insets: insets)
    }
}

public struct AnchoredMenuRow: View {
    private let title: String
    private let identifier: String
    private let isSelected: Bool
    private let action: (CGRect) -> Void
    @Environment(\.anchoredMenuPresentation) private var presentation
    @State private var frame: CGRect = .zero

    public init(_ title: String, identifier: String, isSelected: Bool,
                action: @escaping (CGRect) -> Void) {
        self.title = title
        self.identifier = identifier
        self.isSelected = isSelected
        self.action = action
    }

    public var body: some View {
        Button { action(frame) } label: {
            HStack(spacing: DesignTokens.Spacing.sm) {
                Text(title)
                Spacer(minLength: 0)
                Image(systemName: "chevron.forward")
                    .font(DesignTokens.SymbolSize.menuDisclosure)
                    .foregroundStyle(.secondary)
                    .frame(width: DesignTokens.ButtonIcon.labelArtwork,
                           height: DesignTokens.ButtonIcon.labelArtwork)
            }
        }
        .buttonStyle(AnchoredMenuButtonStyle(isSelected: isSelected))
        .accessibilityIdentifier(identifier)
        .onGeometryChange(for: CGRect.self) { geometry in
            if let presentation {
                geometry.frame(in: .named(presentation.coordinateSpace))
            } else {
                .zero
            }
        } action: { frame = $0 }
    }
}

public struct AnchoredMenuNumber: View {
    private let number: String
    private let title: String
    private let identifier: String
    private let isSelected: Bool
    private let action: () -> Void

    public init(_ number: String, title: String, identifier: String,
                isSelected: Bool, action: @escaping () -> Void) {
        self.number = number
        self.title = title
        self.identifier = identifier
        self.isSelected = isSelected
        self.action = action
    }

    public var body: some View {
        let insets = EdgeInsets(top: DesignTokens.Spacing.xs, leading: DesignTokens.Spacing.xs,
                               bottom: DesignTokens.Spacing.xs, trailing: DesignTokens.Spacing.xs)
        Button(action: action) {
            Text(number)
                .font(DesignTokens.Typography.selectionHeader)
                .lineLimit(1)
                .frame(width: DesignTokens.Interactive.regular, height: DesignTokens.Interactive.regular)
                .background(isSelected ? DesignTokens.Surface.selected : DesignTokens.Surface.elevated,
                            in: DesignTokens.ShapeToken.menuNumber)
                .enchronHoverTarget(visual: DesignTokens.ShapeToken.menuNumber,
                                    interaction: DesignTokens.ShapeToken.menuNumberTarget,
                                    insets: insets)
        }
        .buttonStyle(EnchronPressFeedbackButtonStyle(.control))
        .accessibilityLabel(title)
        .accessibilityIdentifier(identifier)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
