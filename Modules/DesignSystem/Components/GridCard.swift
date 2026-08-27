import SwiftUI

public struct GridCard: View {
    private enum Variant {
        case video(
            artworkURL: URL?,
            fileSize: String,
            duration: String,
            badges: [String],
            watchedProgress: Double?
        )
        case folder(count: Int?)
        case poster(PosterState)
        case episode(EpisodeState)
    }

    public enum SkeletonVariant {
        case video
        case folder
        case poster
        case episode
    }

    struct EpisodeState {
        let artworkURL: URL?
        let numberLabel: String?
        let overview: String?
        let duration: String?
        let watchedProgress: Double?

        init(
            artworkURL: URL?,
            numberLabel: String?,
            overview: String?,
            duration: String?,
            watchedProgress: Double?
        ) {
            self.artworkURL = artworkURL
            self.numberLabel = numberLabel
            self.overview = overview
            self.duration = duration
            self.watchedProgress = watchedProgress.flatMap { progress in
                guard progress.isFinite else { return nil }
                return min(max(progress, 0), 1)
            }
        }
    }

    struct PosterState {
        let artworkURL: URL?
        let watchedProgress: Double?
        let unplayedCount: Int?

        init(
            artworkURL: URL?,
            watchedProgress: Double?,
            unplayedCount: Int?
        ) {
            self.artworkURL = artworkURL
            self.watchedProgress = watchedProgress.flatMap { progress in
                guard progress.isFinite else { return nil }
                return min(max(progress, 0), 1)
            }
            self.unplayedCount = unplayedCount.flatMap { $0 > 0 ? $0 : nil }
        }
    }

    @Namespace private var hoverNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isSkeletonPulsing = false

    private let title: String
    private let variant: Variant
    private let explicitIdentifier: String?
    private let selectionEnabled: Bool
    private let isSelected: Bool
    private let isSkeleton: Bool
    private let action: (() -> Void)?

    private init(
        title: String,
        variant: Variant,
        identifier: String?,
        selectionEnabled: Bool,
        isSelected: Bool,
        isSkeleton: Bool = false,
        action: (() -> Void)?
    ) {
        self.title = title
        self.variant = variant
        self.explicitIdentifier = identifier
        self.selectionEnabled = selectionEnabled
        self.isSelected = isSelected
        self.isSkeleton = isSkeleton
        self.action = action
    }

    public static func video(
        title: String,
        artworkURL: URL? = nil,
        fileSize: String,
        duration: String,
        badges: [String] = [],
        watchedProgress: Double? = nil,
        accessibilityIdentifier: String? = nil,
        selectionEnabled: Bool = false,
        isSelected: Bool = false,
        action: (() -> Void)? = nil
    ) -> GridCard {
        GridCard(
            title: title,
            variant: .video(
                artworkURL: artworkURL,
                fileSize: fileSize,
                duration: duration,
                badges: badges,
                watchedProgress: watchedProgress
            ),
            identifier: accessibilityIdentifier,
            selectionEnabled: selectionEnabled,
            isSelected: isSelected,
            action: action
        )
    }

    public static func folder(
        title: String,
        count: Int?,
        accessibilityIdentifier: String? = nil,
        action: (() -> Void)? = nil
    ) -> GridCard {
        GridCard(
            title: title,
            variant: .folder(count: count),
            identifier: accessibilityIdentifier,
            selectionEnabled: false,
            isSelected: false,
            action: action
        )
    }

    public static func poster(
        title: String,
        artworkURL: URL?,
        watchedProgress: Double? = nil,
        unplayedCount: Int? = nil,
        accessibilityIdentifier: String? = nil,
        selectionEnabled: Bool = false,
        isSelected: Bool = false,
        action: (() -> Void)? = nil
    ) -> GridCard {
        GridCard(
            title: title,
            variant: .poster(
                PosterState(
                    artworkURL: artworkURL,
                    watchedProgress: watchedProgress,
                    unplayedCount: unplayedCount
                )
            ),
            identifier: accessibilityIdentifier,
            selectionEnabled: selectionEnabled,
            isSelected: isSelected,
            action: action
        )
    }

    public static func episode(
        title: String,
        numberLabel: String? = nil,
        overview: String? = nil,
        duration: String? = nil,
        artworkURL: URL?,
        watchedProgress: Double? = nil,
        accessibilityIdentifier: String? = nil,
        action: (() -> Void)? = nil
    ) -> GridCard {
        GridCard(
            title: title,
            variant: .episode(
                EpisodeState(
                    artworkURL: artworkURL,
                    numberLabel: numberLabel,
                    overview: overview,
                    duration: duration,
                    watchedProgress: watchedProgress
                )
            ),
            identifier: accessibilityIdentifier,
            selectionEnabled: false,
            isSelected: false,
            action: action
        )
    }

    public static func skeleton(_ variant: SkeletonVariant) -> GridCard {
        let cardVariant: Variant = switch variant {
        case .video:
            .video(
                artworkURL: nil,
                fileSize: "0 GB",
                duration: "0:00:00",
                badges: [],
                watchedProgress: nil
            )
        case .folder:
            .folder(count: 0)
        case .poster:
            .poster(PosterState(artworkURL: nil, watchedProgress: nil, unplayedCount: nil))
        case .episode:
            .episode(EpisodeState(
                artworkURL: nil,
                numberLabel: "Episode 1",
                overview: "Placeholder episode overview text.",
                duration: "30 min",
                watchedProgress: nil
            ))
        }
        return GridCard(
            title: "Placeholder card title",
            variant: cardVariant,
            identifier: nil,
            selectionEnabled: false,
            isSelected: false,
            isSkeleton: true,
            action: nil
        )
    }

    private var variantKey: String {
        switch variant {
        case .video: return "video"
        case .folder: return "folder"
        case .poster: return "poster"
        case .episode: return "episode"
        }
    }

    private var resolvedIdentifier: String {
        explicitIdentifier ?? "grid-card-\(variantKey)-\(title)"
    }

    private var resolvedLabel: String {
        "\(title), \(variantKey)"
    }

    private var hoverActivationGroup: EnchronHoverGroup {
        EnchronHoverGroup(id: "grid-card-thumbnail-info", in: hoverNamespace, behavior: .activatesGroup)
    }

    private var hoverRevealGroup: EnchronHoverGroup {
        EnchronHoverGroup(id: "grid-card-thumbnail-info", in: hoverNamespace, behavior: .followsGroup)
    }

    public var body: some View {
        if isSkeleton {
            cardVisual
                .redacted(reason: .placeholder)
                .opacity(isSkeletonPulsing ? 0.55 : 1)
                .task(id: reduceMotion) {
                    if reduceMotion {
                        isSkeletonPulsing = false
                    } else {
                        withAnimation(DesignTokens.AnimationToken.skeleton) {
                            isSkeletonPulsing = true
                        }
                    }
                }
                .accessibilityHidden(true)
        } else if let action {
            cardVisual
                .onTapGesture(perform: action)
                .accessibilityElement(children: .ignore)
                .accessibilityIdentifier(resolvedIdentifier)
                .accessibilityLabel(resolvedLabel)
                .accessibilityAddTraits(.isButton)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .accessibilityValue(
                    isSelected ? "Selected" : "Not selected",
                    isEnabled: selectionEnabled
                )
                .accessibilityAction { action() }
        } else {
            cardVisual
                .accessibilityElement(children: .ignore)
                .accessibilityIdentifier(resolvedIdentifier)
                .accessibilityLabel(resolvedLabel)
                .accessibilityAddTraits(.isButton)
        }
    }

    private var cardVisual: some View {
        let shape = DesignTokens.ShapeToken.card
        return ZStack {
            VStack(alignment: .leading, spacing: 0) {
                thumbnailContent(shape)
                    .frame(width: cardWidth, height: thumbnailHeight)
                    .clipShape(shape)
                    .enchronHoverContentShape(shape)
                    .enchronHoverEffect(.highlight, in: hoverActivationGroup)
                    .overlay(alignment: .topTrailing) {
                        if selectionEnabled {
                            selectionIndicator
                                .padding(DesignTokens.Spacing.sm)
                        }
                    }

                if let captionBelowThumbnail {
                    Text(captionBelowThumbnail)
                        .font(DesignTokens.Typography.headline)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, minHeight: 22, maxHeight: 22, alignment: .leading)
                        .padding(.horizontal, DesignTokens.Card.paddingH)
                        .padding(.vertical, DesignTokens.Card.paddingV)
                }
            }

            if selectionEnabled && isSelected {
                shape.strokeBorder(
                    DesignTokens.Theme.accent,
                    lineWidth: DesignTokens.Stroke.bold
                )
                .allowsHitTesting(false)
            }
        }
        .frame(width: cardWidth)
        .clipShape(shape)
        .contentShape(.contextMenuPreview, shape)
        .contentShape(shape)
        .background {
            if selectionEnabled && isSelected {
                shape.fill(DesignTokens.Surface.selected)
            }
        }
        .animation(DesignTokens.AnimationToken.selection, value: isSelected)
    }

    private var cardWidth: CGFloat {
        switch variant {
        case .episode:
            DesignTokens.Card.stillWidth
        case .poster:
            DesignTokens.Card.posterWidth
        case .video, .folder:
            DesignTokens.Card.gridMin
        }
    }

    private var thumbnailHeight: CGFloat {
        switch variant {
        case .poster:
            DesignTokens.Card.posterWidth * 3 / 2
        case .episode:
            DesignTokens.Card.stillHeight
        case .video, .folder:
            DesignTokens.Card.thumbnailHeight
        }
    }

    private var captionBelowThumbnail: String? {
        switch variant {
        case .episode(let episode): episode.numberLabel
        case .video, .folder, .poster: title
        }
    }

    private var selectionIndicator: some View {
        ZStack {
            Circle()
                .fill(
                    isSelected
                        ? DesignTokens.Theme.accent
                        : DesignTokens.Surface.overlay
                )
            Circle()
                .strokeBorder(
                    isSelected
                        ? DesignTokens.Theme.accent
                        : DesignTokens.Surface.accessoryText,
                    lineWidth: isSelected
                        ? DesignTokens.Stroke.bold
                        : DesignTokens.Stroke.regular
                )
            if isSelected {
                Image(systemName: "checkmark")
                    .font(DesignTokens.SymbolSize.compact)
                    .foregroundStyle(.white)
            }
        }
        .frame(
            width: DesignTokens.Interactive.compact,
            height: DesignTokens.Interactive.compact
        )
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func thumbnailContent(_ shape: RoundedRectangle) -> some View {
        if isSkeleton {
            shape.fill(DesignTokens.Surface.elevated)
        } else {
            switch variant {
            case let .video(artworkURL, fileSize, duration, badges, watchedProgress):
                AsyncArtworkImage(url: artworkURL)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    .background(DesignTokens.Surface.elevated)
                    .overlay {
                        videoThumbnailInfo(fileSize: fileSize, duration: duration, badges: badges)
                    }
                    .overlay {
                        if let watchedProgress {
                            watchedProgressBar(watchedProgress)
                        }
                    }
            case let .folder(count):
                shape.fill(DesignTokens.Surface.elevated)
                    .overlay(alignment: .center) {
                        thumbnailPlaceholderIcon("folder.fill")
                    }
                    .overlay(alignment: .bottomLeading) {
                        if let count {
                            folderThumbnailInfo(count: count)
                        }
                    }
            case let .poster(poster):
                AsyncArtworkImage(url: poster.artworkURL)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    .background(DesignTokens.Theme.surfaceContainerHighest)
                    .overlay(alignment: .topTrailing) {
                        if let unplayedCount = poster.unplayedCount {
                            thumbnailBadge("\(unplayedCount)")
                                .enchronSpatialOffset(z: DesignTokens.Spacing.xs)
                                .padding(DesignTokens.Spacing.sm)
                        }
                    }
                    .overlay {
                        if let watchedProgress = poster.watchedProgress {
                            watchedEdgeProgressVisual(watchedProgress)
                        }
                    }
            case let .episode(episode):
                AsyncArtworkImage(url: episode.artworkURL)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    .background(DesignTokens.Theme.surfaceContainerHighest)
                    .overlay {
                        episodeCaption(episode)
                    }
                    .overlay {
                        if let watchedProgress = episode.watchedProgress {
                            watchedEdgeProgressVisual(watchedProgress)
                        }
                    }
            }
        }
    }

    private func episodeCaption(_ episode: EpisodeState) -> some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.25),
                    .init(color: .black.opacity(0.55), location: 0.5),
                    .init(color: .black.opacity(0.9), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            ViewThatFits(in: .vertical) {
                episodeCaptionText(episode, overviewLineLimit: 6)
                episodeCaptionText(episode, overviewLineLimit: 5)
                episodeCaptionText(episode, overviewLineLimit: 4)
                episodeCaptionText(episode, overviewLineLimit: 3)
                episodeCaptionText(episode, overviewLineLimit: 2)
                episodeCaptionText(episode, overviewLineLimit: 1)
                episodeCaptionText(episode, overviewLineLimit: 0)
            }
        }
        .frame(width: cardWidth, height: thumbnailHeight, alignment: .bottomLeading)
        .clipped()
        .enchronHoverOpacity(
            active: 1,
            inactive: 0,
            in: hoverRevealGroup,
            animation: DesignTokens.AnimationToken.controlsTransition
        )
        .allowsHitTesting(false)
    }

    private func episodeCaptionText(
        _ episode: EpisodeState,
        overviewLineLimit: Int
    ) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
            Text(title)
                .font(DesignTokens.Typography.headline)
                .lineLimit(2)
                .truncationMode(.tail)

            if let overview = episode.overview, overviewLineLimit > 0 {
                Text(overview)
                    .font(DesignTokens.Typography.metadata.leading(.tight))
                    .foregroundStyle(DesignTokens.Surface.supportingText)
                    .lineLimit(overviewLineLimit)
            }

            if let duration = episode.duration {
                Label(duration, systemImage: "play.fill")
                    .labelStyle(.titleAndIcon)
                    .font(DesignTokens.Typography.metadata)
                    .padding(.top, DesignTokens.Spacing.xxs)
            }
        }
        .multilineTextAlignment(.leading)
        .frame(width: cardWidth - 2 * DesignTokens.Spacing.sm, alignment: .leading)
        .padding(.horizontal, DesignTokens.Spacing.sm)
        .padding(.bottom, DesignTokens.Spacing.sm)
        .padding(.top, DesignTokens.Spacing.xs)
    }

    private func videoThumbnailInfo(fileSize: String, duration: String, badges: [String]) -> some View {
        VStack {
            HStack {
                Spacer(minLength: 0)
                if !badges.isEmpty {
                    HStack(spacing: DesignTokens.Spacing.xxs) {
                        ForEach(badges, id: \.self) { badge in
                            thumbnailBadge(badge)
                        }
                    }
                }
            }

            Spacer()

            HStack {
                thumbnailMetadata(fileSize)
                Spacer()
                thumbnailMetadata(duration)
            }
        }
        .padding(DesignTokens.Spacing.sm)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .enchronHoverOpacity(
            active: 1,
            inactive: 0,
            in: hoverRevealGroup,
            animation: DesignTokens.AnimationToken.controlsTransition
        )
        .allowsHitTesting(false)
    }

    private func folderThumbnailInfo(count: Int) -> some View {
        HStack {
            thumbnailMetadata("\(count) items")
            Spacer(minLength: 0)
        }
        .padding(DesignTokens.Spacing.sm)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .enchronHoverOpacity(
            active: 1,
            inactive: 0,
            in: hoverRevealGroup,
            animation: DesignTokens.AnimationToken.controlsTransition
        )
        .allowsHitTesting(false)
    }

    private func thumbnailBadge(_ text: String) -> some View {
        Text(text)
            .font(DesignTokens.Typography.badge)
            .foregroundStyle(DesignTokens.Surface.supportingText)
            .padding(.horizontal, DesignTokens.Spacing.xs)
            .padding(.vertical, DesignTokens.Spacing.xxs)
            .enchronGlassBadge()
    }

    private func watchedProgressBar(_ progress: Double) -> some View {
        watchedEdgeProgressVisual(progress)
            .enchronHoverOpacity(
                active: 1,
                inactive: 0,
                in: hoverRevealGroup,
                animation: DesignTokens.AnimationToken.controlsTransition
            )
    }

    private func thumbnailPlaceholderIcon(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: DesignTokens.Card.placeholderIconSize))
            .foregroundStyle(DesignTokens.Surface.supportingText)
    }

    private func thumbnailMetadata(_ text: String) -> some View {
        Text(text)
            .font(DesignTokens.Typography.metadata)
            .foregroundStyle(DesignTokens.Surface.supportingText)
    }
}

func watchedEdgeProgressVisual(_ progress: Double) -> some View {
    let clamped = max(0, min(1, progress))
    let lineWidth = DesignTokens.ProgressBar.watchedEdgeHeight
    return GeometryReader { proxy in
        Rectangle()
            .fill(DesignTokens.Theme.accent)
            .frame(width: proxy.size.width * clamped, height: lineWidth)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .clipShape(DesignTokens.ShapeToken.card)
    }
    .allowsHitTesting(false)
    .accessibilityHidden(true)
}

#if canImport(PreviewsMacros)
private struct GridCardFamilyPreview: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xl) {
                previewRow("Folder and video") {
                    GridCard.folder(title: "Movies", count: 24)
                    GridCard.video(
                        title: "Interstellar",
                        fileSize: "8.2 GB",
                        duration: "2:49:00",
                        badges: ["HDR10+"]
                    )
                    GridCard.video(
                        title: "Blade Runner 2049",
                        fileSize: "45.6 GB",
                        duration: "2:29:55",
                        badges: ["HDR"],
                        watchedProgress: 0.42
                    )
                }

                previewRow("Poster") {
                    GridCard.poster(title: "Arrival", artworkURL: nil)
                    GridCard.poster(
                        title: "Dune: Part Two",
                        artworkURL: nil,
                        watchedProgress: 0.42
                    )
                    GridCard.poster(
                        title: "Severance",
                        artworkURL: nil,
                        unplayedCount: 5
                    )
                    GridCard.skeleton(.poster)
                }

                previewRow("Episode") {
                    GridCard.episode(
                        title: "Pilot",
                        numberLabel: "Episode 1",
                        overview: "American football coach Ted Lasso is hired to coach a wealthy divorcée's English soccer team, AFC Richmond.",
                        duration: "30 min",
                        artworkURL: nil
                    )
                    GridCard.episode(
                        title: "Biscuits",
                        numberLabel: "Episode 2",
                        overview: "It's Ted's first day of coaching, and fans aren't happy. He makes little headway but remains undeterred as the team play their first match.",
                        duration: "29 min",
                        artworkURL: nil,
                        watchedProgress: 0.62
                    )
                    GridCard.skeleton(.episode)
                }
            }
            .padding(DesignTokens.Spacing.xl)
        }
    }

    private func previewRow<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Text(title)
                .font(DesignTokens.Typography.sectionHeader)
                .foregroundStyle(.secondary)

            HStack(alignment: .top, spacing: DesignTokens.Card.gridSpacing) {
                content()
            }
        }
    }
}

private struct GridCardSpacingComparisonPreview: View {
    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxl) {
            comparisonRow(
                "Before · 20 pt",
                spacing: DesignTokens.Spacing.lg
            )
            comparisonRow(
                "After · 16 pt",
                spacing: DesignTokens.Card.gridSpacing
            )
        }
        .padding(DesignTokens.Spacing.xl)
    }

    private func comparisonRow(
        _ title: String,
        spacing: CGFloat
    ) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Text(title)
                .font(DesignTokens.Typography.sectionHeader)
                .foregroundStyle(.secondary)

            HStack(alignment: .top, spacing: spacing) {
                GridCard.folder(title: "Movies", count: 24)
                GridCard.video(
                    title: "Interstellar",
                    fileSize: "8.2 GB",
                    duration: "2:49:00",
                    badges: ["HDR10+"]
                )
                GridCard.video(
                    title: "Blade Runner 2049",
                    fileSize: "45.6 GB",
                    duration: "2:29:55",
                    badges: ["HDR"],
                    watchedProgress: 0.42
                )
            }
        }
    }
}

#Preview("GridCard family") {
    GridCardFamilyPreview()
}

#Preview("GridCard spacing comparison") {
    GridCardSpacingComparisonPreview()
}
#endif
