import SwiftUI

public enum ButtonIconTier {
    case compact
    case standard
    case primary
    case label

    public var artworkSize: CGFloat {
        switch self {
        case .compact: DesignTokens.ButtonIcon.compactArtwork
        case .standard: DesignTokens.ButtonIcon.standardArtwork
        case .primary: DesignTokens.ButtonIcon.primaryArtwork
        case .label: DesignTokens.ButtonIcon.labelArtwork
        }
    }

    var font: Font {
        switch self {
        case .compact: DesignTokens.SymbolSize.compact
        case .standard: DesignTokens.SymbolSize.control
        case .primary: DesignTokens.SymbolSize.action
        case .label: DesignTokens.SymbolSize.label
        }
    }
}

public struct ButtonSymbol: View {
    let systemName: String
    let tier: ButtonIconTier

    public init(
        systemName: String,
        tier: ButtonIconTier = .standard
    ) {
        self.systemName = systemName
        self.tier = tier
    }

    public var body: some View {
        Image(systemName: systemName)
            .font(tier.font)
            .frame(width: tier.artworkSize, height: tier.artworkSize)
    }
}

public struct ButtonIconLabel: View {
    let title: String
    let systemName: String

    public init(title: String, systemName: String) {
        self.title = title
        self.systemName = systemName
    }

    public var body: some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            ButtonSymbol(systemName: systemName, tier: .label)
            Text(title)
                .font(DesignTokens.Typography.metadata)
        }
    }
}
