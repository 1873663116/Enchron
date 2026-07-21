import SwiftUI

struct GridCard: View {
    /// 变体轴:决定缩略图内容与悬停信息布局。缩略图内容由变体内部钉死,不开放给调用点。
    enum Variant {
        case video(fileSize: String, duration: String, badges: [String], watchedProgress: Double?)
        case folder(count: Int)
    }

    @Namespace private var hoverNamespace

    private let title: String
    private let variant: Variant
    private let explicitIdentifier: String?
    /// When set, the whole card is a real interactive control (same contract as
    /// `FileListGroup.Item.action`). When `nil`, the card is display-only — used
    /// by showcase previews. This is what unifies grid and list interaction:
    /// both drive the same routing instead of the grid bolting on an external
    /// `.onTapGesture`, which hit-tested unreliably over the card's own gestures.
    private let action: (() -> Void)?

    private init(title: String, variant: Variant, identifier: String?, action: (() -> Void)?) {
        self.title = title
        self.variant = variant
        self.explicitIdentifier = identifier
        self.action = action
    }

    // MARK: 变体工厂

    static func video(
        title: String,
        fileSize: String,
        duration: String,
        badges: [String] = [],
        /// 0…1 已观看进度;`nil` 表示未看过(不画底部进度描边)。
        watchedProgress: Double? = nil,
        accessibilityIdentifier: String? = nil,
        action: (() -> Void)? = nil
    ) -> GridCard {
        GridCard(
            title: title,
            variant: .video(
                fileSize: fileSize,
                duration: duration,
                badges: badges,
                watchedProgress: watchedProgress
            ),
            identifier: accessibilityIdentifier,
            action: action
        )
    }

    static func folder(
        title: String,
        count: Int,
        accessibilityIdentifier: String? = nil,
        action: (() -> Void)? = nil
    ) -> GridCard {
        GridCard(title: title, variant: .folder(count: count), identifier: accessibilityIdentifier, action: action)
    }

    // MARK: 无障碍派生

    private var variantKey: String {
        switch variant {
        case .video: return "video"
        case .folder: return "folder"
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

    var body: some View {
        if let action {
            cardVisual
                .onTapGesture(perform: action)
                .accessibilityElement(children: .ignore)
                .accessibilityIdentifier(resolvedIdentifier)
                .accessibilityLabel(resolvedLabel)
                .accessibilityAddTraits(.isButton)
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
        return VStack(alignment: .leading, spacing: 0) {
            thumbnailContent(shape)
                .frame(height: DesignTokens.Card.thumbnailHeight)
                .clipShape(shape)
                .glassBackgroundEffect(in: shape)
                .enchronHoverContentShape(shape)
                .enchronHoverEffect(.highlight, in: hoverActivationGroup)

            Text(title)
                .font(DesignTokens.Typography.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, DesignTokens.Card.paddingH)
                .padding(.vertical, DesignTokens.Card.paddingV)
        }
        .frame(width: DesignTokens.Card.gridMin)
        .contentShape(shape)
    }

    @ViewBuilder
    private func thumbnailContent(_ shape: RoundedRectangle) -> some View {
        switch variant {
        case let .video(fileSize, duration, badges, watchedProgress):
            // 缩略图占位 — 真实 app 中为视频帧/海报
            shape.fill(DesignTokens.Surface.elevated)
                .overlay(alignment: .center) {
                    thumbnailPlaceholderIcon("film")
                }
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
                    folderThumbnailInfo(count: count)
                }
        }
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

// 演示:呈现 hover 显示后的底边进度描边,25% / 50% / 100% 三态。
// 静态渲染触发不了 gaze hover,这里直接用视觉本体常显,等价于卡片 hover 后的样子。
private struct WatchedEdgeProgressDemo: View {
    private let shape = DesignTokens.ShapeToken.card
    private let samples: [Double] = [0.25, 0.5, 1.0]

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.xl) {
            ForEach(samples, id: \.self) { p in
                VStack(spacing: DesignTokens.Spacing.sm) {
                    shape.fill(DesignTokens.Surface.elevated)
                        .overlay(alignment: .center) {
                            Image(systemName: "film")
                                .font(.system(size: DesignTokens.Card.placeholderIconSize))
                                .foregroundStyle(DesignTokens.Surface.supportingText)
                        }
                        .overlay { watchedEdgeProgressVisual(p) }
                        .frame(width: DesignTokens.Card.gridMin, height: DesignTokens.Card.thumbnailHeight)
                        .clipShape(shape)
                        .glassBackgroundEffect(in: shape)

                    Text("\(Int(p * 100))%")
                        .font(DesignTokens.Typography.metadata)
                        .foregroundStyle(DesignTokens.Surface.supportingText)
                }
            }
        }
        .padding(DesignTokens.Spacing.xxxl)
    }
}

#Preview("Watched edge · 25/50/100") {
    WatchedEdgeProgressDemo()
}

