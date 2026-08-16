import SwiftUI

public struct GridCard: View {
    /// 变体轴:决定缩略图内容与悬停信息布局。缩略图内容由变体内部钉死,不开放给调用点。
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
    /// When set, the whole card is a real interactive control (same contract as
    /// `FileListGroup.Item.action`). When `nil`, the card is display-only — used
    /// by showcase previews. This is what unifies grid and list interaction:
    /// both drive the same routing instead of the grid bolting on an external
    /// `.onTapGesture`, which hit-tested unreliably over the card's own gestures.
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

    // MARK: 变体工厂

    public static func video(
        title: String,
        artworkURL: URL? = nil,
        fileSize: String,
        duration: String,
        badges: [String] = [],
        /// 0…1 已观看进度;`nil` 表示未看过(不画底部进度描边)。
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

    /// The still fills the whole card and the caption sits on top of it, the way the Apple TV app
    /// lays out an episode. Nothing hangs below the artwork.
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

    // MARK: 无障碍派生

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

    // MARK: 悬停组(@Namespace 按实例隔离,id 字面量可复用)

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
                // Both dimensions are pinned before the clip. Constraining only the height lets an
                // aspect-filled still grow past the card's width and spill onto its neighbours,
                // because the outer width frame centres the oversized thumbnail instead of cutting it.
                thumbnailContent(shape)
                    .frame(width: cardWidth, height: thumbnailHeight)
                    .clipShape(shape)
                    // No glass behind the thumbnail. `glassBackgroundEffect` promotes the card into
                    // its own render layer, which no ancestor can clip, mask or occlude: the card
                    // then draws outside the window at a scroll boundary and pops out of existence
                    // instead of sliding under the sidebar. The thumbnail carries its own fill, so
                    // the glass only ever showed through behind a placeholder.
                    //
                    // The highlight belongs to the artwork alone. Carried by the whole card it also
                    // plates the caption strip underneath, which reads as a panel appearing out of
                    // nowhere around the card's lower half.
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

    /// What the card is called underneath its artwork. An episode is captioned by its number alone:
    /// its title and description belong to the still, where they appear on hover.
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

    // 集信息与其压暗渐变一起随卡片 hover 组显隐;未 hover 时整张剧照干净无遮挡。
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

            // 集号、标题与时长必须完整可读,简介让出行数直到整块放得下,所以候选按简介
            // 行数递减排列,最后一个完全不显示简介。
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
        // Pinned to the card's own box and anchored at its bottom leading corner. Left to size itself
        // around its text, the caption ends up wider than the card and centred over it, which pushes
        // its first characters past the card's leading edge and into the clip.
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
                    // Tighter line height than the title's, so the description reads as one block of
                    // secondary text rather than as more lines of the same weight.
                    .font(DesignTokens.Typography.metadata.leading(.tight))
                    .foregroundStyle(DesignTokens.Surface.supportingText)
                    .lineLimit(overviewLineLimit)
            }

            // The number is carried by the caption under the card, so the still shows only what
            // that caption cannot: the episode's title, its description and its runtime.
            if let duration = episode.duration {
                Label(duration, systemImage: "play.fill")
                    .labelStyle(.titleAndIcon)
                    .font(DesignTokens.Typography.metadata)
                    .padding(.top, DesignTokens.Spacing.xxs)
            }
        }
        .multilineTextAlignment(.leading)
        // The text column is measured, not inferred. `ViewThatFits` gives its candidates no width to
        // work with, so a column that asks for the space it is offered ends up wider than the card
        // and hangs off both sides, losing its first characters to the card's clip.
        .frame(width: cardWidth - 2 * DesignTokens.Spacing.sm, alignment: .leading)
        // Enough to clear the corner curve at the bottom, and no more: the still is small, so every
        // point spent on margin is a point the description loses.
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

    // 底部已观看进度描边(UC-FILE-26)。嵌入卡片底边:thin 描边随缩略图 clipShape 贴合圆角,
    // 仅 hover 时随缩略图 hover 组显隐;未 hover 不显示。视觉本体见 `watchedEdgeProgressVisual`。
    private func watchedProgressBar(_ progress: Double) -> some View {
        watchedEdgeProgressVisual(progress)
            .enchronHoverOpacity(
                active: 1,
                inactive: 0,
                in: hoverRevealGroup,
                animation: DesignTokens.AnimationToken.controlsTransition
            )
    }

    // 居中占位图标:无缩略图时的视频/文件夹标识。视频与文件夹共用同一尺寸与前景色,避免分叉。
    private func thumbnailPlaceholderIcon(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: DesignTokens.Card.placeholderIconSize))
            .foregroundStyle(DesignTokens.Surface.supportingText)
    }

    // 元数据与占位图标统一用 Surface.supportingText(token);视频与文件夹一致。
    private func thumbnailMetadata(_ text: String) -> some View {
        Text(text)
            .font(DesignTokens.Typography.metadata)
            .foregroundStyle(DesignTokens.Surface.supportingText)
    }
}

// 已观看进度描边的纯视觉本体(无 hover 门控):把卡片当作【直角矩形】画满整条底边
// (全宽,贴底,高 = watchedEdgeHeight 的 `Theme.accent` 细线),圆角交给卡片的
// `clipShape` 收口——超出圆角的部分被系统自动裁掉,描边两端顺圆角自然收尾。
// 进度从左铺,width = 全宽 × progress,100% 占满整条底边。无未看段 track。
// 整体填满卡片尺寸,作 `.overlay { }` 叠在缩略图上(clipShape 在 overlay 之后,故会裁)。
func watchedEdgeProgressVisual(_ progress: Double) -> some View {
    let clamped = max(0, min(1, progress))
    let lineWidth = DesignTokens.ProgressBar.watchedEdgeHeight
    return GeometryReader { proxy in
        Rectangle()
            .fill(DesignTokens.Theme.accent)
            .frame(width: proxy.size.width * clamped, height: lineWidth)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            // 自己按卡片圆角 clip:全宽直线在圆角处被弧线切掉,两端顺圆角收口,不外溢。
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

#Preview("GridCard family") {
    GridCardFamilyPreview()
}
#endif
