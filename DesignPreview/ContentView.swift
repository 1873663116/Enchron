import SwiftUI

// MARK: - Preview routing

enum DesignPreviewPage: String, CaseIterable, Identifiable {
    case components
    case spacing
    case radiusAndShapes
    case interactionAndLayout
    case typographyAndSymbols
    case surfaceAndStroke
    case animation
    case pressFeedback
    case settingListGroup
    case centerSlider
    case sceneCard
    case componentStandards

    var id: String { rawValue }

    var title: String {
        switch self {
        case .components: "Components"
        case .spacing: "Spacing"
        case .radiusAndShapes: "Radius & Shapes"
        case .interactionAndLayout: "Interaction & Layout"
        case .typographyAndSymbols: "Typography & Symbols"
        case .surfaceAndStroke: "Surface & Stroke"
        case .animation: "Animation"
        case .pressFeedback: "Press Feedback"
        case .settingListGroup: "Setting List Group"
        case .centerSlider: "Center Slider"
        case .sceneCard: "Scene Card"
        case .componentStandards: "Component Standards"
        }
    }
}

struct ContentView: View {
    @State private var selection: DesignPreviewPage? = .components

    var body: some View {
        NavigationSplitView {
            List(DesignPreviewPage.allCases, selection: $selection) { page in
                Text(page.title)
                    .tag(page)
            }
            .navigationTitle("Design Preview")
        } detail: {
            switch selection ?? .components {
            case .components:
                ComponentLibraryView()
            case .spacing:
                SpacingScalePreview()
            case .radiusAndShapes:
                RadiusShapesPreview()
            case .interactionAndLayout:
                InteractionLayoutPreview()
            case .typographyAndSymbols:
                TypographySymbolsPreview()
            case .surfaceAndStroke:
                SurfaceStrokePreview()
            case .animation:
                AnimationTokensPreview()
            case .pressFeedback:
                PressFeedbackPreview()
            case .settingListGroup:
                SettingListGroupPreview()
            case .centerSlider:
                CenterSliderPreview()
            case .sceneCard:
                SceneCardPreview()
            case .componentStandards:
                ComponentStandardsPreview()
            }
        }
    }
}

#Preview(windowStyle: .automatic) {
    ContentView()
}

// MARK: - Setting list group

struct SettingListGroupPreview: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
                Text("Setting List Group")
                    .font(DesignTokens.Typography.title)
                    .foregroundStyle(.primary)

                VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
                    SettingListGroup(items: [
                        .init(
                            title: "Display",
                            systemName: "display",
                            detail: "Tune brightness, colour profile, and how the playback window scales when you move it closer or further away.",
                            expansion: .top
                        ),
                        .init(
                            title: "Spatial Audio",
                            systemName: "speaker.wave.3",
                            detail: "Render sound that stays anchored to the screen as you look around, with head tracking applied to every channel.",
                            expansion: .center
                        ),
                        .init(
                            title: "Subtitles",
                            systemName: "captions.bubble",
                            detail: "Pick a default language, sizing, and background style for captions, applied across every video you open.",
                            expansion: .bottom
                        ),
                    ])
                    .frame(width: 580)

                    SettingListGroup(items: [
                        .init(
                            title: "Copy Diagnostic Summary",
                            systemName: "doc.on.doc",
                            accessory: .action(
                                title: "Copy",
                                feedback: "Copied",
                                systemName: "doc.on.doc",
                                role: .normal,
                                action: {}
                            )
                        ),
                    ])
                    .frame(width: 580)

                    SettingListGroup(items: [
                        .init(
                            title: "Logging Level",
                            systemName: "list.bullet.rectangle",
                            accessory: .menu(
                                title: "Info",
                                options: [
                                    .init("Off"),
                                    .init("Info"),
                                    .init("Debug"),
                                    .init("Trace"),
                                ]
                            )
                        ),
                        .init(
                            title: "Run Media Diagnostics",
                            systemName: "waveform.path.ecg",
                            accessory: .action(
                                title: "Run",
                                feedback: "Queued",
                                systemName: "play.fill",
                                role: .normal,
                                action: {}
                            )
                        ),
                        .init(
                            title: "Clear App Cache",
                            systemName: "trash",
                            accessory: .action(
                                title: "Clear",
                                feedback: nil,
                                systemName: nil,
                                role: .destructive,
                                action: {}
                            )
                        )
                    ])
                    .frame(width: 580)
                }
            }
            .padding(DesignTokens.Spacing.xxl)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .navigationTitle("Setting List Group")
    }
}

// MARK: - Center slider

struct CenterSliderPreview: View {
    @State private var exposure = 0
    @State private var fineAdjust = -2

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxl) {
                Text("Center Slider")
                    .font(DesignTokens.Typography.title)
                    .foregroundStyle(.primary)

                sliderRow(
                    "Exposure",
                    value: $exposure,
                    leading: "sun.min",
                    trailing: "sun.max"
                )

                sliderRow(
                    "Fine Adjust",
                    value: $fineAdjust,
                    leading: "minus",
                    trailing: "plus"
                )
            }
            .padding(DesignTokens.Spacing.xxl)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .navigationTitle("Center Slider")
    }

    private func sliderRow(
        _ title: String,
        value: Binding<Int>,
        leading: String,
        trailing: String
    ) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            // Review-only readout; the component itself never shows a number.
            HStack(spacing: DesignTokens.Spacing.sm) {
                Text(title)
                    .font(DesignTokens.Typography.headline)
                Text(value.wrappedValue > 0 ? "+\(value.wrappedValue)" : "\(value.wrappedValue)")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }

            CenterSlider(
                value: value,
                leadingSystemImage: leading,
                trailingSystemImage: trailing,
                accessibilityLabel: title,
                accessibilityIdentifier: "DesignPreview-CenterSlider-\(title)"
            )
        }
    }
}

// MARK: - Scene card

struct SceneCardPreview: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .center, spacing: DesignTokens.Spacing.xl) {
                FeaturedSceneCard()
            }
            .padding(DesignTokens.Spacing.xxl)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .navigationTitle("Scene Card")
    }
}

// MARK: - Shared token table

struct TokenRow: Identifiable {
    let id = UUID()
    let name: String
    let value: String
    let note: String
}

struct TokenSection<Content: View>: View {
    let title: String
    let rows: [TokenRow]
    let content: Content

    init(title: String, rows: [TokenRow], @ViewBuilder content: () -> Content) {
        self.title = title
        self.rows = rows
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            Text(title)
                .font(DesignTokens.Typography.sectionHeader)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            content

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                ForEach(rows) { row in
                    HStack(alignment: .firstTextBaseline, spacing: DesignTokens.Spacing.md) {
                        Text(row.name)
                            .font(.system(.caption, design: .monospaced))
                            .frame(width: 220, alignment: .leading)
                        Text(row.value)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(width: 140, alignment: .leading)
                        Text(row.note)
                            .font(DesignTokens.Typography.metadata)
                            .foregroundStyle(.tertiary)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, DesignTokens.Spacing.md)
                    .frame(minHeight: 36)
                    .enchronGlassMenuItem()
                }
            }
        }
        .padding(DesignTokens.Spacing.lg)
        .enchronGlassPanel()
    }
}

private struct TokenPage<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xl) {
                content
            }
            .padding(DesignTokens.Spacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(title)
    }
}

private func valueString(_ value: CGFloat) -> String {
    if value == .greatestFiniteMagnitude {
        return "full"
    }
    return String(format: "%.1fpt", value)
}

// MARK: - Spacing

struct SpacingScalePreview: View {
    private let rows = [
        TokenRow(name: "DesignTokens.Spacing.xxs", value: "4pt", note: "hover gap, micro adjustment"),
        TokenRow(name: "DesignTokens.Spacing.xs", value: "8pt", note: "compact padding, icon gaps"),
        TokenRow(name: "DesignTokens.Spacing.sm", value: "12pt", note: "medium padding, list item spacing"),
        TokenRow(name: "DesignTokens.Spacing.md", value: "16pt", note: "standard padding"),
        TokenRow(name: "DesignTokens.Spacing.lg", value: "20pt", note: "panel padding, section spacing"),
        TokenRow(name: "DesignTokens.Spacing.xl", value: "24pt", note: "large gaps"),
        TokenRow(name: "DesignTokens.Spacing.xxl", value: "32pt", note: "section dividers"),
        TokenRow(name: "DesignTokens.Spacing.xxxl", value: "48pt", note: "extra-large margins"),
    ]

    var body: some View {
        TokenPage(title: "Spacing") {
            TokenSection(title: "Spacing Scale", rows: rows) {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                    spacingRow("xxs", DesignTokens.Spacing.xxs)
                    spacingRow("xs", DesignTokens.Spacing.xs)
                    spacingRow("sm", DesignTokens.Spacing.sm)
                    spacingRow("md", DesignTokens.Spacing.md)
                    spacingRow("lg", DesignTokens.Spacing.lg)
                    spacingRow("xl", DesignTokens.Spacing.xl)
                    spacingRow("xxl", DesignTokens.Spacing.xxl)
                    spacingRow("xxxl", DesignTokens.Spacing.xxxl)
                }
            }
        }
    }

    private func spacingRow(_ name: String, _ value: CGFloat) -> some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            Text(name)
                .font(.system(.body, design: .monospaced))
                .frame(width: 60, alignment: .trailing)
            Text(valueString(value))
                .font(DesignTokens.Typography.metadata)
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .trailing)
            RoundedRectangle(cornerRadius: DesignTokens.Radius.small, style: .continuous)
                .fill(Color.accentColor.opacity(0.65))
                .frame(width: max(value * 4, 16), height: 20)
        }
    }
}

// MARK: - Radius & shapes

struct RadiusShapesPreview: View {
    private let radiusRows = [
        TokenRow(name: "DesignTokens.Radius.panel", value: "40pt", note: "large panels, settings pages, detail views"),
        TokenRow(name: "DesignTokens.Radius.card", value: "32pt", note: "cards, menus, mid-level containers"),
        TokenRow(name: "DesignTokens.Radius.element", value: "24pt", note: "menu items, toolbar, inner containers"),
        TokenRow(name: "DesignTokens.Radius.small", value: "12pt", note: "tags, thumbnails, small rounded backgrounds"),
        TokenRow(name: "DesignTokens.Radius.full", value: "full", note: "circles and capsules"),
        TokenRow(name: "DesignTokens.Radius.concentric", value: "function", note: "inner radius = outer radius - padding"),
    ]

    private let shapeRows = [
        TokenRow(name: "DesignTokens.ShapeToken.panel", value: "radius 40", note: "large panel shape"),
        TokenRow(name: "DesignTokens.ShapeToken.card", value: "radius 32", note: "card and menu container shape"),
        TokenRow(name: "DesignTokens.ShapeToken.element", value: "radius 24", note: "menu item and toolbar shape"),
    ]

    var body: some View {
        TokenPage(title: "Radius & Shapes") {
            TokenSection(title: "Radius Tokens", rows: radiusRows) {
                HStack(alignment: .bottom, spacing: DesignTokens.Spacing.xl) {
                    radiusDemo("panel", DesignTokens.Radius.panel, width: 220, height: 130)
                    radiusDemo("card", DesignTokens.Radius.card, width: 190, height: 112)
                    radiusDemo("element", DesignTokens.Radius.element, width: 160, height: 88)
                    radiusDemo("small", DesignTokens.Radius.small, width: 120, height: 64)
                    capsuleDemo()
                }
            }

            TokenSection(title: "Shape Tokens", rows: shapeRows) {
                HStack(spacing: DesignTokens.Spacing.xl) {
                    shapeDemo("panel", DesignTokens.ShapeToken.panel, width: 220, height: 130)
                    shapeDemo("card", DesignTokens.ShapeToken.card, width: 190, height: 112)
                    shapeDemo("element", DesignTokens.ShapeToken.element, width: 160, height: 88)
                }
            }

            TokenSection(title: "Concentric Examples", rows: [
                TokenRow(name: "panel -> card", value: "40 - 8 = 32", note: "panel containing a card"),
                TokenRow(name: "card -> element", value: "32 - 8 = 24", note: "menu containing a row"),
            ]) {
                HStack(spacing: DesignTokens.Spacing.xl) {
                    concentricDemo(title: "panel -> card", outer: DesignTokens.Radius.panel, inner: DesignTokens.Radius.card)
                    concentricDemo(title: "card -> element", outer: DesignTokens.Radius.card, inner: DesignTokens.Radius.element)
                }
            }
        }
    }

    private func radiusDemo(_ title: String, _ radius: CGFloat, width: CGFloat, height: CGFloat) -> some View {
        VStack(spacing: DesignTokens.Spacing.xs) {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(DesignTokens.Surface.elevated)
                .frame(width: width, height: height)
            Text("\(title) \(valueString(radius))")
                .font(DesignTokens.Typography.metadata)
                .foregroundStyle(.secondary)
        }
    }

    private func capsuleDemo() -> some View {
        VStack(spacing: DesignTokens.Spacing.xs) {
            Capsule()
                .fill(DesignTokens.Surface.elevated)
                .frame(width: 132, height: DesignTokens.Interactive.regular)
            Text("full / Capsule")
                .font(DesignTokens.Typography.metadata)
                .foregroundStyle(.secondary)
        }
    }

    private func shapeDemo(_ title: String, _ shape: some Shape, width: CGFloat, height: CGFloat) -> some View {
        VStack(spacing: DesignTokens.Spacing.xs) {
            shape
                .fill(DesignTokens.Surface.elevated)
                .frame(width: width, height: height)
                .overlay {
                    shape.stroke(DesignTokens.Surface.border, lineWidth: DesignTokens.Stroke.regular)
                }
            Text(title)
                .font(DesignTokens.Typography.metadata)
                .foregroundStyle(.secondary)
        }
    }

    private func concentricDemo(title: String, outer: CGFloat, inner: CGFloat) -> some View {
        VStack(spacing: DesignTokens.Spacing.xs) {
            ZStack {
                RoundedRectangle(cornerRadius: outer, style: .continuous)
                    .fill(DesignTokens.Surface.card)
                    .frame(width: 220, height: 140)
                RoundedRectangle(cornerRadius: inner, style: .continuous)
                    .fill(DesignTokens.Surface.overlay)
                    .frame(width: 204, height: 124)
            }
            Text(title)
                .font(DesignTokens.Typography.metadata)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Interaction & layout

struct InteractionLayoutPreview: View {
    private let interactiveRows = [
        TokenRow(name: "DesignTokens.Interactive.mini", value: "28pt", note: "disclosure, auxiliary controls"),
        TokenRow(name: "DesignTokens.Interactive.compact", value: "36pt", note: "compact scrubbers and dense icon controls"),
        TokenRow(name: "DesignTokens.Interactive.regular", value: "44pt", note: "standard buttons"),
        TokenRow(name: "DesignTokens.Interactive.large", value: "60pt", note: "navigation buttons, self-sufficient target"),
        TokenRow(name: "DesignTokens.Interactive.xl", value: "64pt", note: "primary action"),
        TokenRow(name: "DesignTokens.Interactive.rowHeight", value: "60pt", note: "menu/list row minimum height"),
        TokenRow(name: "DesignTokens.Interactive.buttonSpacing", value: "16pt", note: "minimum spacing between stacked buttons"),
    ]

    private let layoutRows = [
        TokenRow(name: "DesignTokens.Layout.playerControlsWidth", value: "680pt", note: "PlayerControlsView and NLETimelineView panel width"),
        TokenRow(name: "DesignTokens.Layout.ornamentGap", value: "20pt", note: "ornament overlap with window bottom edge"),
    ]

    private let progressBarRows = [
        TokenRow(name: "DesignTokens.ProgressBar.thumbDiameter", value: "24pt", note: "standard draggable scrubber button"),
        TokenRow(name: "DesignTokens.ProgressBar.trackHeight", value: "24pt", note: "active drag track height"),
        TokenRow(name: "DesignTokens.ProgressBar.inactiveScale", value: "0.66", note: "unfocused and hover track height scale"),
        TokenRow(name: "DesignTokens.ProgressBar.inactiveTrackHeight", value: "15.8pt", note: "track height before active drag"),
        TokenRow(name: "DesignTokens.ProgressBar.hitHeight", value: "60pt", note: "hover and drag target height"),
        TokenRow(name: "DesignTokens.ProgressBar.previewWidth", value: "680pt", note: "Design Preview player progress width"),
        TokenRow(name: "DesignTokens.ProgressBar.timeBubbleOffset", value: "24pt", note: "time readout above scrubber"),
        TokenRow(name: "DesignTokens.ProgressBar.playedColor", value: "white 0.72", note: "played portion in normal state"),
        TokenRow(name: "DesignTokens.ProgressBar.unplayedColor", value: "white 0.16", note: "unplayed portion in normal state"),
    ]

    var body: some View {
        TokenPage(title: "Interaction & Layout") {
            TokenSection(title: "Interactive Sizes", rows: interactiveRows) {
                HStack(alignment: .bottom, spacing: DesignTokens.Spacing.xl) {
                    interactiveItem("mini", DesignTokens.Interactive.mini)
                    interactiveItem("compact", DesignTokens.Interactive.compact)
                    interactiveItem("regular", DesignTokens.Interactive.regular)
                    interactiveItem("large", DesignTokens.Interactive.large)
                    interactiveItem("xl", DesignTokens.Interactive.xl)
                    rowHeightDemo()
                    spacingDemo()
                }
            }

            TokenSection(title: "Layout Dimensions", rows: layoutRows) {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
                    dimensionBar("playerControlsWidth", DesignTokens.Layout.playerControlsWidth, maxWidth: 680)
                    dimensionBar("ornamentGap", DesignTokens.Layout.ornamentGap, maxWidth: 220)
                }
            }

            TokenSection(title: "Progress Bar", rows: progressBarRows) {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
                    PlayerProgressStrip()
                    HStack(alignment: .bottom, spacing: DesignTokens.Spacing.xl) {
                        progressBarDimension("thumb", DesignTokens.ProgressBar.thumbDiameter)
                        progressBarDimension("track", DesignTokens.ProgressBar.trackHeight)
                        dimensionBar("hitHeight", DesignTokens.ProgressBar.hitHeight, maxWidth: 220)
                    }
                }
            }
        }
    }

    private func interactiveItem(_ name: String, _ size: CGFloat) -> some View {
        VStack(spacing: DesignTokens.Spacing.xs) {
            ZStack {
                Circle()
                    .stroke(style: StrokeStyle(lineWidth: DesignTokens.Stroke.regular, dash: [4, 3]))
                    .foregroundStyle(.tertiary)
                    .frame(width: DesignTokens.Interactive.large, height: DesignTokens.Interactive.large)
                Circle()
                    .fill(Color.accentColor.opacity(0.2))
                    .frame(width: size, height: size)
            }
            Text("\(name) \(Int(size))")
                .font(DesignTokens.Typography.metadata)
                .foregroundStyle(.secondary)
        }
    }

    private func rowHeightDemo() -> some View {
        VStack(spacing: DesignTokens.Spacing.xs) {
            HStack {
                Image(systemName: "film")
                Text("rowHeight")
                Spacer()
                Text("60")
            }
            .font(DesignTokens.Typography.metadata)
            .padding(.horizontal, DesignTokens.Spacing.md)
            .frame(width: 180, height: DesignTokens.Interactive.rowHeight)
            .enchronGlassMenuItem()
            Text("rowHeight")
                .font(DesignTokens.Typography.metadata)
                .foregroundStyle(.secondary)
        }
    }

    private func spacingDemo() -> some View {
        VStack(spacing: DesignTokens.Spacing.xs) {
            HStack(spacing: DesignTokens.Interactive.buttonSpacing) {
                Circle().fill(Color.accentColor.opacity(0.25)).frame(width: 44, height: 44)
                Circle().fill(Color.accentColor.opacity(0.25)).frame(width: 44, height: 44)
            }
            .frame(height: DesignTokens.Interactive.large)
            Text("buttonSpacing")
                .font(DesignTokens.Typography.metadata)
                .foregroundStyle(.secondary)
        }
    }

    private func progressBarDimension(_ title: String, _ size: CGFloat) -> some View {
        VStack(spacing: DesignTokens.Spacing.xs) {
            if title == "thumb" {
                Circle()
                    .fill(.white)
                    .overlay {
                        Circle()
                            .strokeBorder(DesignTokens.Theme.accent, lineWidth: DesignTokens.Stroke.bold)
                    }
                    .frame(width: size, height: size)
            } else {
                Capsule()
                    .fill(DesignTokens.Theme.accent)
                    .frame(width: DesignTokens.ProgressBar.thumbDiameter * 2, height: size)
            }
            Text("\(title) \(Int(size))")
                .font(DesignTokens.Typography.metadata)
                .foregroundStyle(.secondary)
        }
    }

    private func dimensionBar(_ title: String, _ width: CGFloat, maxWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            Text("\(title)  \(Int(width))pt")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
            RoundedRectangle(cornerRadius: DesignTokens.Radius.small, style: .continuous)
                .fill(Color.accentColor.opacity(0.35))
                .frame(width: min(width, maxWidth), height: 28)
        }
    }
}

// MARK: - Typography & symbols

struct TypographySymbolsPreview: View {
    private let typographyRows = [
        TokenRow(name: "DesignTokens.Typography.title", value: ".title2", note: "video titles, page headings"),
        TokenRow(name: "DesignTokens.Typography.headline", value: ".headline", note: "card titles, section labels"),
        TokenRow(name: "DesignTokens.Typography.metadata", value: ".caption", note: "resolution, file size, date metadata"),
        TokenRow(name: "DesignTokens.Typography.sectionHeader", value: ".caption2", note: "section headers"),
        TokenRow(name: "DesignTokens.Typography.badge", value: ".caption", note: "badge labels"),
        TokenRow(name: "DesignTokens.Typography.monospacedDetail", value: "9pt medium mono", note: "timecode and ruler text"),
    ]

    private let symbolRows = [
        TokenRow(name: "DesignTokens.SymbolSize.control", value: "24pt semibold", note: "skip and seek buttons"),
        TokenRow(name: "DesignTokens.SymbolSize.card", value: "36pt", note: "card and folder icons"),
        TokenRow(name: "DesignTokens.SymbolSize.action", value: "36pt medium", note: "play/pause primary action"),
        TokenRow(name: "DesignTokens.SymbolSize.feature", value: "44pt", note: "scene selector and large UI icons"),
        TokenRow(name: "DesignTokens.SymbolSize.hero", value: "48pt", note: "hero detail view icons"),
        TokenRow(name: "DesignTokens.SymbolSize.giant", value: "60pt", note: "empty state placeholder icons"),
    ]

    var body: some View {
        TokenPage(title: "Typography & Symbols") {
            TokenSection(title: "Typography", rows: typographyRows) {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
                    Text("Title")
                        .font(DesignTokens.Typography.title)
                    Text("Headline")
                        .font(DesignTokens.Typography.headline)
                    Text("Metadata")
                        .font(DesignTokens.Typography.metadata)
                        .foregroundStyle(.secondary)
                    Text("SECTION HEADER")
                        .font(DesignTokens.Typography.sectionHeader)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    Text("HDR10+")
                        .font(DesignTokens.Typography.badge)
                        .padding(.horizontal, DesignTokens.Spacing.xs)
                        .padding(.vertical, DesignTokens.Spacing.xxs)
                        .enchronGlassBadge()
                    Text("00:12:34.56")
                        .font(DesignTokens.Typography.monospacedDetail)
                        .foregroundStyle(.secondary)
                }
            }

            TokenSection(title: "Symbol Sizes", rows: symbolRows) {
                HStack(alignment: .bottom, spacing: DesignTokens.Spacing.xl) {
                    symbolItem("control", DesignTokens.SymbolSize.control)
                    symbolItem("card", DesignTokens.SymbolSize.card)
                    symbolItem("action", DesignTokens.SymbolSize.action)
                    symbolItem("feature", DesignTokens.SymbolSize.feature)
                    symbolItem("hero", DesignTokens.SymbolSize.hero)
                    symbolItem("giant", DesignTokens.SymbolSize.giant)
                }
            }
        }
    }

    private func symbolItem(_ name: String, _ font: Font) -> some View {
        VStack(spacing: DesignTokens.Spacing.xs) {
            Image(systemName: "play.fill")
                .font(font)
            Text(name)
                .font(DesignTokens.Typography.metadata)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Surface & stroke

struct SurfaceStrokePreview: View {
    private let surfaceRows = [
        TokenRow(name: "DesignTokens.Surface.card", value: "white 0.03", note: "card background"),
        TokenRow(name: "DesignTokens.Surface.elevated", value: "white 0.04", note: "elevated panel background"),
        TokenRow(name: "DesignTokens.Surface.overlay", value: "white 0.06", note: "overlay / brighter surface"),
        TokenRow(name: "DesignTokens.Surface.selected", value: "white 0.08", note: "selected state background"),
        TokenRow(name: "DesignTokens.Surface.border", value: "white 0.05", note: "subtle border"),
        TokenRow(name: "DesignTokens.Surface.focusBorder", value: "theme accent", note: "focused input/control border"),
    ]

    private let strokeRows = [
        TokenRow(name: "DesignTokens.Stroke.subtle", value: "0.5pt", note: "card borders, unselected state"),
        TokenRow(name: "DesignTokens.Stroke.regular", value: "1.0pt", note: "timeline major ticks"),
        TokenRow(name: "DesignTokens.Stroke.bold", value: "1.5pt", note: "playhead, selected state borders"),
    ]

    var body: some View {
        TokenPage(title: "Surface & Stroke") {
            TokenSection(title: "Surface Tiers", rows: surfaceRows) {
                HStack(spacing: DesignTokens.Spacing.md) {
                    surfaceItem("card", DesignTokens.Surface.card)
                    surfaceItem("elevated", DesignTokens.Surface.elevated)
                    surfaceItem("overlay", DesignTokens.Surface.overlay)
                    surfaceItem("selected", DesignTokens.Surface.selected)
                    surfaceItem("border", DesignTokens.Surface.border)
                    surfaceItem("focusBorder", DesignTokens.Surface.focusBorder)
                }
            }

            TokenSection(title: "Stroke Widths", rows: strokeRows) {
                HStack(spacing: DesignTokens.Spacing.xl) {
                    strokeItem("subtle", DesignTokens.Stroke.subtle)
                    strokeItem("regular", DesignTokens.Stroke.regular)
                    strokeItem("bold", DesignTokens.Stroke.bold)
                }
            }
        }
    }

    private func surfaceItem(_ title: String, _ color: Color) -> some View {
        VStack(spacing: DesignTokens.Spacing.xs) {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.small, style: .continuous)
                .fill(color)
                .frame(width: 92, height: 92)
                .overlay {
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.small, style: .continuous)
                        .strokeBorder(DesignTokens.Surface.border, lineWidth: DesignTokens.Stroke.regular)
                }
            Text(title)
                .font(DesignTokens.Typography.metadata)
                .foregroundStyle(.secondary)
        }
    }

    private func strokeItem(_ title: String, _ width: CGFloat) -> some View {
        VStack(spacing: DesignTokens.Spacing.xs) {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.small, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(0.75), lineWidth: width)
                .frame(width: 120, height: 72)
            Text("\(title) \(String(format: "%.1f", width))")
                .font(DesignTokens.Typography.metadata)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Animation

struct AnimationTokensPreview: View {
    @State private var activeToken: String?
    @State private var skeletonPulse = false

    private let rows = [
        TokenRow(name: "DesignTokens.AnimationToken.controlsTransition", value: "easeInOut 0.4s", note: "controls show/hide"),
        TokenRow(name: "DesignTokens.AnimationToken.panelSpring", value: "spring 0.35 b0.15", note: "panel expand/collapse"),
        TokenRow(name: "DesignTokens.AnimationToken.menuPopup", value: "spring 0.35 b0.15", note: "menu/popover popup"),
        TokenRow(name: "DesignTokens.AnimationToken.selection", value: "bouncy 0.4 +0.1", note: "selection state change"),
        TokenRow(name: "DesignTokens.AnimationToken.playback", value: "spring r0.45 d0.85", note: "play/pause state"),
        TokenRow(name: "DesignTokens.AnimationToken.scene", value: "spring r0.3 d0.7", note: "cinema environment switch"),
        TokenRow(name: "DesignTokens.AnimationToken.fadeIn", value: "easeIn 0.25s", note: "content fade-in"),
        TokenRow(name: "DesignTokens.AnimationToken.skeleton", value: "easeInOut 1s repeat", note: "skeleton loading pulse"),
        TokenRow(name: "DesignTokens.LoadingSpinner.headAnimation", value: "easeOut 0.7s", note: "spinner head extension"),
        TokenRow(name: "DesignTokens.LoadingSpinner.tailAnimation", value: "easeOut 0.55s", note: "spinner tail catch-up"),
        TokenRow(name: "DesignTokens.LoadingSpinner.headDuration", value: "700ms", note: "spinner head phase duration"),
        TokenRow(name: "DesignTokens.LoadingSpinner.tailDuration", value: "550ms", note: "spinner tail phase duration"),
    ]

    var body: some View {
        TokenPage(title: "Animation") {
            TokenSection(title: "Animation Tokens", rows: rows) {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                    animationRow("controlsTransition", DesignTokens.AnimationToken.controlsTransition)
                    animationRow("panelSpring", DesignTokens.AnimationToken.panelSpring)
                    animationRow("menuPopup", DesignTokens.AnimationToken.menuPopup)
                    animationRow("selection", DesignTokens.AnimationToken.selection)
                    animationRow("playback", DesignTokens.AnimationToken.playback)
                    animationRow("scene", DesignTokens.AnimationToken.scene)
                    animationRow("fadeIn", DesignTokens.AnimationToken.fadeIn)
                    skeletonRow()
                }
            }
        }
    }

    private func animationRow(_ name: String, _ animation: Animation) -> some View {
        let isActive = activeToken == name
        return Button {
            withAnimation(animation) {
                activeToken = isActive ? nil : name
            }
        } label: {
            HStack(spacing: DesignTokens.Spacing.md) {
                Text(name)
                    .font(.system(.body, design: .monospaced))
                    .frame(width: 190, alignment: .leading)
                RoundedRectangle(cornerRadius: DesignTokens.Radius.small, style: .continuous)
                    .fill(isActive ? Color.accentColor.opacity(0.65) : DesignTokens.Surface.elevated)
                    .frame(width: isActive ? 220 : 64, height: 36)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, DesignTokens.Spacing.md)
            .frame(height: DesignTokens.Interactive.rowHeight)
            .enchronGlassMenuItem()
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("DesignPreview-Tokens-animation-\(name)")
        .accessibilityLabel("Preview \(name) animation")
    }

    private func skeletonRow() -> some View {
        Button {
            skeletonPulse.toggle()
        } label: {
            HStack(spacing: DesignTokens.Spacing.md) {
                Text("skeleton")
                    .font(.system(.body, design: .monospaced))
                    .frame(width: 190, alignment: .leading)
                HStack(spacing: DesignTokens.Spacing.xs) {
                    skeletonBlock(width: 160, opacity: skeletonPulse ? 0.22 : 0.55)
                    skeletonBlock(width: 72, opacity: skeletonPulse ? 0.55 : 0.22)
                }
                .animation(DesignTokens.AnimationToken.skeleton, value: skeletonPulse)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, DesignTokens.Spacing.md)
            .frame(height: DesignTokens.Interactive.rowHeight)
            .enchronGlassMenuItem()
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("DesignPreview-Tokens-animation-skeleton")
        .accessibilityLabel("Preview skeleton animation")
    }

    private func skeletonBlock(width: CGFloat, opacity: Double) -> some View {
        RoundedRectangle(cornerRadius: DesignTokens.Radius.small, style: .continuous)
            .fill(Color.accentColor.opacity(opacity))
            .frame(width: width, height: 24)
    }
}

// MARK: - Press feedback

struct PressFeedbackPreview: View {
    private let rows = [
        TokenRow(name: "DesignTokens.PressFeedback.card", value: "scale 0.97", note: "cards and broad spatial surfaces"),
        TokenRow(name: "DesignTokens.PressFeedback.row", value: "scale 0.985", note: "menu rows and list items"),
        TokenRow(name: "DesignTokens.PressFeedback.control", value: "scale 0.96", note: "control capsules and grouped controls"),
        TokenRow(name: "DesignTokens.PressFeedback.icon", value: "scale 0.90", note: "individual icon targets, stronger return spring"),
    ]

    var body: some View {
        TokenPage(title: "Press Feedback") {
            TokenSection(title: "Press Feedback Tokens", rows: rows) {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
                        Text("Tap each real component shape to compare the feedback.")
                            .font(DesignTokens.Typography.metadata)
                            .foregroundStyle(.secondary)

                        HStack(alignment: .center, spacing: DesignTokens.Spacing.xl) {
                            pressCardPreview
                            pressRowPreview
                            pressControlPreview
                            pressIconPreview
                        }
                    }

                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                        pressTokenRow(name: "DesignTokens.PressFeedback.card", spec: DesignTokens.PressFeedback.card, scenario: "Cards")
                        pressTokenRow(name: "DesignTokens.PressFeedback.row", spec: DesignTokens.PressFeedback.row, scenario: "Rows")
                        pressTokenRow(name: "DesignTokens.PressFeedback.control", spec: DesignTokens.PressFeedback.control, scenario: "Controls")
                        pressTokenRow(name: "DesignTokens.PressFeedback.icon", spec: DesignTokens.PressFeedback.icon, scenario: "Icons")
                    }
                }
            }
        }
    }

    private var pressCardPreview: some View {
        VStack(spacing: DesignTokens.Spacing.xs) {
            VideoCardLarge(
                title: "Card",
                fileSize: scaleText(DesignTokens.PressFeedback.card),
                duration: DesignTokens.PressFeedback.card.holdDurationLabel,
                badges: ["CARD"]
            )
            Text("card · broad surface")
                .font(DesignTokens.Typography.metadata)
                .foregroundStyle(.tertiary)
        }
    }

    private var pressRowPreview: some View {
        VStack(spacing: DesignTokens.Spacing.xs) {
            Button {} label: {
                HStack(spacing: DesignTokens.Spacing.sm) {
                    Image(systemName: "list.bullet")
                        .font(.body)
                        .frame(width: 24)
                        .foregroundStyle(.secondary)
                    Text("Row")
                        .font(.body)
                    Spacer()
                    Text(scaleText(DesignTokens.PressFeedback.row))
                        .font(DesignTokens.Typography.metadata)
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, DesignTokens.Spacing.md)
                .frame(width: 280, height: DesignTokens.Interactive.rowHeight)
                .enchronGlassMenuItem()
            }
            .buttonStyle(.plain)
            .enchronPressFeedback(.row)
            .accessibilityIdentifier("DesignPreview-PressFeedback-button-row")
            .accessibilityLabel("Preview row press feedback")

            Text("row · list item")
                .font(DesignTokens.Typography.metadata)
                .foregroundStyle(.tertiary)
        }
    }

    private var pressControlPreview: some View {
        VStack(spacing: DesignTokens.Spacing.xs) {
            Button {} label: {
                HStack(spacing: DesignTokens.ControlBar.buttonSpacing) {
                    Image(systemName: "backward.fill")
                        .font(DesignTokens.SymbolSize.control)
                    Image(systemName: "play.fill")
                        .font(DesignTokens.SymbolSize.action)
                    Image(systemName: "forward.fill")
                        .font(DesignTokens.SymbolSize.control)
                }
                .foregroundStyle(.secondary)
                .frame(width: 180, height: DesignTokens.Interactive.large)
                .enchronGlassControl()
            }
            .buttonStyle(.plain)
            .enchronPressFeedback(.control)
            .accessibilityIdentifier("DesignPreview-PressFeedback-button-control")
            .accessibilityLabel("Preview control press feedback")

            Text("control · capsule")
                .font(DesignTokens.Typography.metadata)
                .foregroundStyle(.tertiary)
        }
    }

    private var pressIconPreview: some View {
        VStack(spacing: DesignTokens.Spacing.xs) {
            Button {} label: {
                Image(systemName: "play.fill")
                    .font(DesignTokens.SymbolSize.control)
                    .foregroundStyle(.secondary)
                    .frame(width: DesignTokens.Interactive.regular,
                           height: DesignTokens.Interactive.regular)
                    .clipShape(Circle())
                    .glassBackgroundEffect(in: Circle())
                    .contentShape(.hoverEffect, Circle())
                    .hoverEffect(.automatic)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .padding((DesignTokens.Interactive.large - DesignTokens.Interactive.regular) / 2)
            .enchronPressFeedback(.icon)
            .accessibilityIdentifier("DesignPreview-PressFeedback-button-icon")
            .accessibilityLabel("Preview icon press feedback")

            Text("icon · single target")
                .font(DesignTokens.Typography.metadata)
                .foregroundStyle(.tertiary)
        }
    }

    private func pressTokenRow(
        name: String,
        spec: DesignTokens.PressFeedbackSpec,
        scenario: String
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DesignTokens.Spacing.md) {
            Text(name)
                .font(.system(.caption, design: .monospaced))
                .frame(width: 220, alignment: .leading)
            Text(String(format: "%.3f", spec.pressedScale))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .leading)
            Text("max \(valueString(spec.maximumVisualInset))")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 84, alignment: .leading)
            Text(spec.pressAnimationLabel)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 112, alignment: .leading)
            Text(spec.releaseAnimationLabel)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 136, alignment: .leading)
            Text(spec.holdDurationLabel)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .leading)
            Text(scenario)
                .font(DesignTokens.Typography.metadata)
                .foregroundStyle(.tertiary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
        .frame(minHeight: 36)
        .enchronGlassMenuItem()
    }

    private func scaleText(_ spec: DesignTokens.PressFeedbackSpec) -> String {
        String(format: "%.3f", spec.pressedScale)
    }
}

// MARK: - Component standards

struct ComponentStandardsPreview: View {
    private let cardRows = [
        TokenRow(name: "DesignTokens.Card.paddingH", value: "16pt", note: "horizontal padding inside card text area"),
        TokenRow(name: "DesignTokens.Card.paddingV", value: "14pt", note: "vertical padding inside card text area"),
        TokenRow(name: "DesignTokens.Card.gridMin", value: "224pt", note: "adaptive grid minimum card width"),
        TokenRow(name: "DesignTokens.Card.thumbnailHeight", value: "140pt", note: "thumbnail height for grid cards"),
        TokenRow(name: "DesignTokens.Card.gridSpacing", value: "20pt", note: "grid inter-item spacing"),
    ]

    private let menuRows = [
        TokenRow(name: "DesignTokens.Menu.glassPadding", value: "8pt", note: "glass inset padding"),
        TokenRow(name: "DesignTokens.Menu.panelWidth", value: "190pt", note: "main menu panel width"),
        TokenRow(name: "DesignTokens.Menu.submenuWidth", value: "200pt", note: "submenu panel width"),
    ]

    private let controlRows = [
        TokenRow(name: "DesignTokens.ControlBar.width", value: "680pt", note: "matches Layout.playerControlsWidth"),
        TokenRow(name: "DesignTokens.ControlBar.buttonSpacing", value: "24pt", note: "spacing between playback controls"),
        TokenRow(name: "DesignTokens.ControlBar.paddingH", value: "32pt", note: "horizontal padding inside control capsule"),
        TokenRow(name: "DesignTokens.ControlBar.paddingV", value: "12pt", note: "vertical padding inside control capsule"),
        TokenRow(name: "DesignTokens.ControlBar.primaryFill", value: "white 0.72", note: "primary play button fill"),
        TokenRow(name: "DesignTokens.ControlBar.primarySymbol", value: "black 0.78", note: "primary play symbol color"),
    ]

    var body: some View {
        TokenPage(title: "Component Standards") {
            TokenSection(title: "Card", rows: cardRows) {
                VideoCardLarge(title: "Interstellar", fileSize: "8.2 GB", duration: "2:49:00", badges: ["HDR10+"])
            }

            TokenSection(title: "Menu", rows: menuRows) {
                HStack(alignment: .top, spacing: DesignTokens.Spacing.xs) {
                    VStack(spacing: DesignTokens.Spacing.xxs) {
                        MenuItemRow(title: "Audio Track", isExpanded: true)
                        MenuItemRow(title: "Subtitle", isExpanded: false)
                    }
                    .padding(DesignTokens.Menu.glassPadding)
                    .frame(width: DesignTokens.Menu.panelWidth)
                    .enchronGlassMenu()

                    VStack(spacing: DesignTokens.Spacing.xxs) {
                        SubMenuItemRow(title: "English 5.1", isChecked: true)
                        SubMenuItemRow(title: "Japanese 2.0", isChecked: false)
                    }
                    .padding(DesignTokens.Menu.glassPadding)
                    .frame(width: DesignTokens.Menu.submenuWidth)
                    .enchronGlassMenu()
                }
            }

            TokenSection(title: "Control Bar", rows: controlRows) {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
                    dimensionBar("width", DesignTokens.ControlBar.width, maxWidth: 360)
                    PlayerControlBar()
                }
            }
        }
    }

    private func dimensionBar(_ title: String, _ width: CGFloat, maxWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            Text("\(title)  \(Int(width))pt")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
            RoundedRectangle(cornerRadius: DesignTokens.Radius.small, style: .continuous)
                .fill(Color.accentColor.opacity(0.35))
                .frame(width: min(width, maxWidth), height: 28)
                .overlay(alignment: .trailing) {
                    Text("scaled")
                        .font(DesignTokens.Typography.metadata)
                        .foregroundStyle(.tertiary)
                        .padding(.trailing, DesignTokens.Spacing.xs)
                }
        }
    }

    private func spacingBlock(_ title: String) -> some View {
        RoundedRectangle(cornerRadius: DesignTokens.Radius.small, style: .continuous)
            .fill(DesignTokens.Surface.elevated)
            .frame(width: DesignTokens.Interactive.regular, height: DesignTokens.Interactive.regular)
            .overlay {
                Text(title)
                    .font(DesignTokens.Typography.metadata)
                    .foregroundStyle(.secondary)
            }
    }
}
