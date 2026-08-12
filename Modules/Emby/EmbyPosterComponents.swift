import DesignSystem
import SwiftUI

public struct EmbyPosterItem: Identifiable, Equatable, Hashable, Sendable {
    public let id: EmbyItemID
    public let title: String
    public let progress: Double?
    public let unplayedCount: Int?

    public init(
        id: EmbyItemID,
        title: String,
        progress: Double? = nil,
        unplayedCount: Int? = nil
    ) {
        self.id = id
        self.title = title
        self.progress = progress.flatMap { value in
            guard value.isFinite else { return nil }
            return min(max(value, 0), 1)
        }
        self.unplayedCount = unplayedCount.flatMap { $0 > 0 ? $0 : nil }
    }
}

public struct EmbyPosterCard<Artwork: View>: View {
    private let item: EmbyPosterItem
    private let action: () -> Void
    private let artwork: () -> Artwork

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        item: EmbyPosterItem,
        action: @escaping () -> Void = {},
        @ViewBuilder artwork: @escaping () -> Artwork
    ) {
        self.item = item
        self.action = action
        self.artwork = artwork
    }

    public var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                poster

                Text(item.title)
                    .font(DesignTokens.Typography.headline)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .padding(.horizontal, DesignTokens.Card.paddingH)
                    .padding(.vertical, DesignTokens.Card.paddingV)
                    .frame(
                        maxWidth: .infinity,
                        minHeight: DesignTokens.Interactive.rowHeight + DesignTokens.Spacing.lg,
                        alignment: .topLeading
                    )
            }
            .frame(width: DesignTokens.Card.gridMin)
            .background(DesignTokens.Surface.card)
            .clipShape(DesignTokens.ShapeToken.card)
            .overlay {
                DesignTokens.ShapeToken.card.strokeBorder(
                    DesignTokens.Surface.border,
                    lineWidth: DesignTokens.Stroke.subtle
                )
            }
            .enchronHoverContentShape(DesignTokens.ShapeToken.card)
            .enchronHoverEffect(reduceMotion ? .highlight : .lift)
            .contentShape(DesignTokens.ShapeToken.card)
        }
        .buttonStyle(
            EnchronPressFeedbackButtonStyle(
                .card,
                playsSensoryFeedback: true
            )
        )
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("Emby-PosterCard-\(item.id.rawValue)")
        .accessibilityLabel(item.title)
        .accessibilityValue(accessibilityValue)
        .accessibilityAddTraits(.isButton)
    }

    private var poster: some View {
        ZStack(alignment: .topTrailing) {
            artwork()
                .frame(
                    width: DesignTokens.Card.gridMin,
                    height: DesignTokens.Card.gridMin * 3 / 2
                )
                .clipped()

            if let unplayedCount = item.unplayedCount {
                Text("\(unplayedCount)")
                    .font(DesignTokens.Typography.badge)
                    .fontWeight(.bold)
                    .padding(.horizontal, DesignTokens.Spacing.xs)
                    .padding(.vertical, DesignTokens.Spacing.xxs)
                    .enchronGlassBadge()
                    .enchronSpatialOffset(z: DesignTokens.Spacing.xs)
                    .padding(DesignTokens.Spacing.sm)
            }
        }
        .frame(
            width: DesignTokens.Card.gridMin,
            height: DesignTokens.Card.gridMin * 3 / 2
        )
        .background(DesignTokens.Theme.surfaceContainerHighest)
        .overlay(alignment: .bottom) {
            if let progress = item.progress {
                GeometryReader { geometry in
                    DesignTokens.Surface.overlay
                        .overlay(alignment: .leading) {
                            DesignTokens.Theme.accent
                                .frame(width: geometry.size.width * progress)
                        }
                }
                .frame(height: DesignTokens.ProgressBar.watchedEdgeHeight)
                .accessibilityHidden(true)
            }
        }
        .accessibilityHidden(true)
    }

    private var accessibilityValue: String {
        var values: [String] = []
        if let progress = item.progress {
            values.append("\(Int((progress * 100).rounded())) percent watched")
        }
        if let unplayedCount = item.unplayedCount {
            values.append("\(unplayedCount) unplayed")
        }
        return values.joined(separator: ", ")
    }
}

public struct EmbyPosterShelf<Artwork: View>: View {
    private let title: String
    private let items: [EmbyPosterItem]
    private let onSelect: (EmbyPosterItem) -> Void
    private let artwork: (EmbyPosterItem) -> Artwork

    public init(
        title: String,
        items: [EmbyPosterItem],
        onSelect: @escaping (EmbyPosterItem) -> Void = { _ in },
        @ViewBuilder artwork: @escaping (EmbyPosterItem) -> Artwork
    ) {
        self.title = title
        self.items = items
        self.onSelect = onSelect
        self.artwork = artwork
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
            Text(title)
                .font(DesignTokens.Typography.title)

            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: DesignTokens.Card.gridSpacing) {
                    ForEach(items) { item in
                        EmbyPosterCard(
                            item: item,
                            action: { onSelect(item) }
                        ) {
                            artwork(item)
                        }
                    }
                }
                .padding(.vertical, DesignTokens.Spacing.sm)
            }
            .scrollIndicators(.hidden)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }
}

public struct EmbyPosterSkeletonCard: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPulsing = false

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DesignTokens.ShapeToken.card
                .fill(DesignTokens.Theme.surfaceContainerHighest)
                .frame(
                    width: DesignTokens.Card.gridMin,
                    height: DesignTokens.Card.gridMin * 3 / 2
                )

            Text("Placeholder poster title")
                .font(DesignTokens.Typography.headline)
                .lineLimit(2)
                .padding(.horizontal, DesignTokens.Card.paddingH)
                .padding(.vertical, DesignTokens.Card.paddingV)
                .frame(
                    maxWidth: .infinity,
                    minHeight: DesignTokens.Interactive.rowHeight + DesignTokens.Spacing.lg,
                    alignment: .topLeading
                )
                .redacted(reason: .placeholder)
        }
        .frame(width: DesignTokens.Card.gridMin)
        .background(DesignTokens.Surface.card)
        .clipShape(DesignTokens.ShapeToken.card)
        .overlay {
            DesignTokens.ShapeToken.card.strokeBorder(
                DesignTokens.Surface.border,
                lineWidth: DesignTokens.Stroke.subtle
            )
        }
        .opacity(isPulsing ? 0.55 : 1)
        .task(id: reduceMotion) {
            if reduceMotion {
                isPulsing = false
            } else {
                withAnimation(DesignTokens.AnimationToken.skeleton) {
                    isPulsing = true
                }
            }
        }
        .accessibilityHidden(true)
    }
}

public struct EmbyPosterPlaceholder: View {
    private let title: String

    public init(title: String = "") {
        self.title = title
    }

    public var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    DesignTokens.Theme.accent.opacity(0.58),
                    DesignTokens.Surface.overlay,
                    DesignTokens.Theme.surfaceContainerHighest,
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(spacing: DesignTokens.Spacing.sm) {
                Image(systemName: "film.stack.fill")
                    .font(DesignTokens.SymbolSize.giant)

                if !title.isEmpty {
                    Text(title)
                        .font(DesignTokens.Typography.headline)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, DesignTokens.Spacing.lg)
                }
            }
            .foregroundStyle(DesignTokens.Surface.accessoryText)
        }
        .accessibilityHidden(true)
    }
}
