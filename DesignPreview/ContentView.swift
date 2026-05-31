import SwiftUI

// MARK: - Preview routing

enum DesignPreviewPage: String, CaseIterable, Identifiable {
    // MARK: Components (front)
    case components
    case sidebar
    case settingListGroup
    case playerSettingsPanel
    case centerSlider
    case sceneCard
    // MARK: Design Tokens (back)
    case spacing
    case radiusAndShapes
    case interactionAndLayout
    case typographyAndSymbols
    case surfaceAndStroke
    case animation
    case pressFeedback
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
        case .sidebar: "Sidebar"
        case .settingListGroup: "Setting List Group"
        case .playerSettingsPanel: "Player Settings Panel"
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
            .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)
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
            case .sidebar:
                SidebarPreview()
            case .settingListGroup:
                SettingListGroupPreview()
            case .playerSettingsPanel:
                PlayerSettingsPanelPreview()
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

// MARK: - Sidebar

struct SidebarPreview: View {
    var body: some View {
        ScrollView {
            SourceSidebarSection()
                .padding(DesignTokens.Spacing.xxl)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .navigationTitle("Sidebar")
    }
}

// MARK: - Setting list group

struct SettingListGroupPreview: View {
    @State private var showClearCacheConfirm = false
    @State private var selectedSpecialCardID = "day"
    @State private var specialSliderValue = 0
    @State private var specialAuto = true

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

                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                        Text("Special Controls")
                            .font(DesignTokens.Typography.headline)
                            .foregroundStyle(.primary)

                        SettingListGroup(items: [
                            .init(
                                id: "special-card-selection",
                                title: "Scene",
                                accessory: .none,
                                embeddedControl: .cardSelection(
                                    options: [
                                        .init(id: "day", title: "Day", systemName: "sun.max.fill"),
                                        .init(id: "night", title: "Night", systemName: "moon.stars.fill"),
                                    ],
                                    selectedID: $selectedSpecialCardID
                                )
                            ),
                            .init(
                                id: "special-center-slider",
                                title: "Curve",
                                accessory: .none,
                                embeddedControl: .centerSlider(
                                    value: $specialSliderValue,
                                    leadingSystemImage: "rectangle",
                                    trailingSystemImage: "capsule",
                                    accessibilityLabel: "Curve"
                                )
                            ),
                            .init(
                                id: "special-plain-list",
                                title: "Auto",
                                accessory: .boundToggle(isOn: $specialAuto, isEnabled: true, marker: nil)
                            ),
                        ])
                        .frame(width: 720)
                    }

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
                                action: { showClearCacheConfirm = true }
                            )
                        )
                    ])
                    .frame(width: 580)

                    SettingListGroup(items: [
                        .init(
                            title: "Performance HUD",
                            systemName: "gauge",
                            accessory: .toggle(isOn: false)
                        ),
                        .init(
                            title: "Cache Size",
                            systemName: "internaldrive",
                            accessory: .value("1.8 GB")
                        ),
                        .init(
                            title: "Version & Build",
                            systemName: "info.circle",
                            accessory: .valueAction(
                                value: "0.1.0 (42)",
                                actionTitle: "Copy",
                                feedback: "Copied",
                                action: {}
                            )
                        ),
                        .init(
                            title: "Current Media Inspector",
                            systemName: "list.bullet.rectangle",
                            keyValueDetail: [
                                .init(key: "Codec", value: "HEVC Main10"),
                                .init(key: "Resolution", value: "3840 x 2160"),
                                .init(key: "HDR", value: "HDR10 metadata detected")
                            ],
                            expansion: .top,
                            accessory: .automatic
                        )
                    ])
                    .frame(width: 580)

                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                        Text("File List Group")
                            .font(DesignTokens.Typography.headline)
                            .foregroundStyle(.primary)

                        FileListGroup(items: [
                            .folder(title: "Movies", itemCount: 24),
                            .folder(title: "Spatial", itemCount: 12),
                            .video(title: "Interstellar", fileSize: "8.2 GB", duration: "2:49:00", badges: ["HDR10+"]),
                            .video(title: "Blade Runner 2049", fileSize: "45.6 GB", duration: "2:29:55", badges: ["MV-HEVC"])
                        ])
                        .frame(width: 580)
                    }
                }
            }
            .padding(DesignTokens.Spacing.xxl)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .navigationTitle("Setting List Group")
        .enchronDestructiveConfirmation(
            "Clear App Cache?",
            message: "This removes thumbnails and temporary cache. It does not delete video files or playback history.",
            confirmTitle: "Clear",
            isPresented: $showClearCacheConfirm,
            onConfirm: {}
        )
    }
}

// MARK: - Player settings panel

struct PlayerSettingsPanelPreview: View {
    @State private var selectedCategory: PlayerPanelSettingsCategory = .sceneSetting
    @State private var selectedSceneID = "day"
    @State private var selectedPositionID = "left"
    @State private var sceneAuto = true
    @State private var screenCurve = 0
    @State private var screenHeight = 0
    @State private var screenDistance = 0
    @State private var screenSize = 0
    @State private var threeDMode = false
    @State private var immersiveMode: ImmersiveVideoMode = .off
    @State private var hdrEnabled = false
    @State private var exposure = 0
    @State private var shadows = 0
    @State private var highlights = 0
    @State private var contrast = 0
    @State private var whites = 0
    @State private var temperature = 0
    @State private var tint = 0
    @State private var saturation = 0
    @State private var vibrance = 0
    @State private var sharpness = 0
    @State private var showResetConfirm = false

    private enum ImmersiveVideoMode {
        case off
        case oneEighty
        case threeSixty
    }

    private let panelWidth: CGFloat = 980
    private let panelHeight: CGFloat = 560
    private let detailColumnWidth: CGFloat = 720

    var body: some View {
        panelContainer
            .navigationTitle("Player Settings Panel")
            .enchronDestructiveConfirmation(
                "Restore Default Settings?",
                message: "This resets the panel preview controls to their default positions.",
                confirmTitle: "Restore",
                isPresented: $showResetConfirm,
                onConfirm: restoreDefaults
            )
    }

    private var panelContainer: some View {
        let panelShape = DesignTokens.ShapeToken.panel

        return HStack(alignment: .top, spacing: 0) {
            sidebar
                .padding(.leading, DesignTokens.SourceSidebar.windowInset)
                .padding(.vertical, DesignTokens.SourceSidebar.windowInset)

            detailPanel
                .padding(.leading, DesignTokens.SourceSidebar.trailingContentGap)
                .padding(.trailing, DesignTokens.SourceSidebar.windowInset)
                .padding(.vertical, DesignTokens.SourceSidebar.windowInset)
        }
        .frame(width: panelWidth, height: panelHeight, alignment: .topLeading)
        .clipShape(panelShape)
        .glassBackgroundEffect(.plate, in: panelShape, displayMode: .always)
        .padding(DesignTokens.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var sidebar: some View {
        let shape = DesignTokens.SourceSidebar.shape

        return VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
            Text("Panel")
                .font(DesignTokens.SourceSidebar.sectionTitleFont)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .padding(.horizontal, DesignTokens.SourceSidebar.contentPaddingH)

            VStack(spacing: DesignTokens.SourceSidebar.rowSpacing) {
                ForEach(PlayerPanelSettingsCategory.allCases) { category in
                    sidebarRow(category)
                }
            }
            .padding(.horizontal, DesignTokens.SourceSidebar.listPaddingH)

            Spacer(minLength: 0)
        }
        .padding(.vertical, DesignTokens.SourceSidebar.contentPaddingV)
        .frame(width: DesignTokens.SourceSidebar.width)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .clipShape(shape)
        .glassBackgroundEffect(.plate, in: shape, displayMode: .always)
        .accessibilityIdentifier("DesignPreview-PlayerSettingsPanel-sidebar")
    }

    private var detailPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xl) {
                Text(selectedCategory.title)
                    .font(DesignTokens.Typography.title)
                    .foregroundStyle(.white)

                detailContent
            }
            .padding(.vertical, DesignTokens.Spacing.xxxl)
            .frame(width: detailColumnWidth, alignment: .topLeading)
        }
        .scrollIndicators(.hidden)
        .mask(PlayerSettingsPanelScrollFadeMask())
        .frame(width: detailColumnWidth)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .accessibilityIdentifier("DesignPreview-PlayerSettingsPanel-detail")
    }

    @ViewBuilder
    private var detailContent: some View {
        switch selectedCategory {
        case .sceneSetting:
            sceneSettingContent
        case .playMode:
            playModeContent
        case .advanced:
            advancedContent
        }
    }

    private var sceneSettingContent: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xl) {
            panelSection("Scene") {
                SettingListGroup(items: [
                    .init(
                        id: "scene-day-night",
                        title: "Scene",
                        accessory: .none,
                        embeddedControl: .cardSelection(
                            options: [
                                .init(id: "day", title: "Day", systemName: "sun.max.fill"),
                                .init(id: "night", title: "Night", systemName: "moon.stars.fill"),
                            ],
                            selectedID: $selectedSceneID
                        )
                    ),
                    .init(
                        id: "scene-auto",
                        title: "Auto",
                        accessory: .boundToggle(isOn: $sceneAuto, isEnabled: true, marker: nil)
                    ),
                ])
            }

            panelSection("Screen Setting") {
                SettingListGroup(items: [
                    sliderItem(
                        id: "screen-curve",
                        title: "Curve",
                        value: $screenCurve,
                        leadingSystemImage: "rectangle",
                        trailingSystemImage: "capsule"
                    ),
                    sliderItem(
                        id: "screen-height",
                        title: "Height",
                        value: $screenHeight,
                        leadingSystemImage: "arrow.down",
                        trailingSystemImage: "arrow.up"
                    ),
                    sliderItem(
                        id: "screen-distance",
                        title: "Distance",
                        value: $screenDistance,
                        leadingSystemImage: "smallcircle.filled.circle",
                        trailingSystemImage: "circle"
                    ),
                    sliderItem(
                        id: "screen-size",
                        title: "Size",
                        value: $screenSize,
                        leadingSystemImage: "arrow.down.right.and.arrow.up.left",
                        trailingSystemImage: "arrow.up.left.and.arrow.down.right"
                    ),
                ])
            }

            panelSection("Position") {
                SettingListGroup(items: [
                    .init(
                        id: "screen-position",
                        title: "Position",
                        accessory: .none,
                        embeddedControl: .cardSelection(
                            options: [
                                .init(id: "left", title: "Left", systemName: "arrow.left"),
                                .init(id: "center", title: "Center", systemName: "dot.square"),
                                .init(id: "right", title: "Right", systemName: "arrow.right"),
                            ],
                            selectedID: $selectedPositionID
                        )
                    ),
                ])
            }

            SettingListGroup(items: [
                .init(
                    id: "restore-default-settings",
                    title: "Restore Default Settings",
                    systemName: "arrow.counterclockwise",
                    accessory: .action(
                        title: "Restore",
                        feedback: nil,
                        systemName: nil,
                        role: .destructive,
                        action: { showResetConfirm = true }
                    )
                ),
            ])
        }
    }

    private var playModeContent: some View {
        SettingListGroup(items: [
            .init(
                id: "play-mode-3d",
                title: "3D",
                systemName: "cube.transparent",
                accessory: .boundToggle(isOn: $threeDMode, isEnabled: false, marker: "2D source")
            ),
            .init(
                id: "play-mode-180",
                title: "180° Immersive Video",
                systemName: "circle.lefthalf.filled",
                accessory: .boundToggle(isOn: immersive180Binding, isEnabled: true, marker: nil)
            ),
            .init(
                id: "play-mode-360",
                title: "360° Immersive Video",
                systemName: "rotate.3d",
                accessory: .boundToggle(isOn: immersive360Binding, isEnabled: true, marker: nil)
            ),
        ])
    }

    private var advancedContent: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xl) {
            SettingListGroup(items: [
                .init(
                    id: "advanced-hdr",
                    title: "HDR",
                    systemName: "sun.max.trianglebadge.exclamationmark",
                    supportingText: "Dolby Vision fallback to HDR10",
                    accessory: .boundToggle(isOn: $hdrEnabled, isEnabled: true, marker: nil)
                ),
            ])

            panelSection("Color") {
                SettingListGroup(items: [
                    sliderItem(
                        id: "color-exposure",
                        title: "Exposure",
                        value: $exposure,
                        leadingSystemImage: "dial.min",
                        trailingSystemImage: "plusminus.circle"
                    ),
                    sliderItem(
                        id: "color-shadows",
                        title: "Shadows",
                        value: $shadows,
                        leadingSystemImage: "circle.righthalf.filled",
                        trailingSystemImage: "circle.lefthalf.striped.horizontal"
                    ),
                    sliderItem(
                        id: "color-highlights",
                        title: "Highlights",
                        value: $highlights,
                        leadingSystemImage: "circle.lefthalf.striped.horizontal",
                        trailingSystemImage: "circle.righthalf.filled"
                    ),
                    sliderItem(
                        id: "color-contrast",
                        title: "Contrast",
                        value: $contrast,
                        leadingSystemImage: "circle.lefthalf.filled",
                        trailingSystemImage: "circle.righthalf.filled"
                    ),
                    sliderItem(
                        id: "color-whites",
                        title: "Whites",
                        value: $whites,
                        leadingSystemImage: "sun.min",
                        trailingSystemImage: "sun.max"
                    ),
                    sliderItem(
                        id: "color-temperature",
                        title: "Temperature",
                        value: $temperature,
                        leadingSystemImage: "snowflake",
                        trailingSystemImage: "thermometer.sun.fill"
                    ),
                    sliderItem(
                        id: "color-tint",
                        title: "Tint",
                        value: $tint,
                        leadingSystemImage: "drop",
                        trailingSystemImage: "drop.fill"
                    ),
                    sliderItem(
                        id: "color-saturation",
                        title: "Saturation",
                        value: $saturation,
                        leadingSystemImage: "paintpalette",
                        trailingSystemImage: "paintpalette.fill"
                    ),
                    sliderItem(
                        id: "color-vibrance",
                        title: "Vibrance",
                        value: $vibrance,
                        leadingSystemImage: "sparkle",
                        trailingSystemImage: "sparkles"
                    ),
                    sliderItem(
                        id: "color-sharpness",
                        title: "Sharpness",
                        value: $sharpness,
                        leadingSystemImage: "circle.dotted",
                        trailingSystemImage: "scope"
                    ),
                ])
            }
        }
    }

    private var immersive180Binding: Binding<Bool> {
        Binding {
            immersiveMode == .oneEighty
        } set: { isOn in
            withAnimation(DesignTokens.AnimationToken.selection) {
                immersiveMode = isOn ? .oneEighty : .off
            }
        }
    }

    private var immersive360Binding: Binding<Bool> {
        Binding {
            immersiveMode == .threeSixty
        } set: { isOn in
            withAnimation(DesignTokens.AnimationToken.selection) {
                immersiveMode = isOn ? .threeSixty : .off
            }
        }
    }

    private func sidebarRow(_ category: PlayerPanelSettingsCategory) -> some View {
        EditableSourceSidebarRow(
            icon: category.icon,
            title: category.title,
            isSelected: selectedCategory == category,
            isEnabled: true,
            isOnline: false,
            isDeletable: false,
            isSelectionMode: false,
            isChecked: false,
            isAppearing: false,
            isSwipeExpanded: false,
            isDragging: false,
            rowOffset: 0,
            allowsReordering: false,
            allowsSwipe: false,
            onTap: {
                withAnimation(DesignTokens.AnimationToken.selection) {
                    selectedCategory = category
                }
            },
            onToggleSelection: {},
            onSwipeBegan: {},
            onSwipeExpanded: {},
            onSwipeCollapsed: {},
            onDelete: {},
            onReorderBegan: {},
            onReorderChanged: { _ in },
            onReorderEnded: {}
        )
        .accessibilityIdentifier("DesignPreview-PlayerSettingsPanel-category-\(category.id)")
    }

    private func panelSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Text(title)
                .font(DesignTokens.Typography.headline)
                .foregroundStyle(.primary)

            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sliderItem(
        id: String,
        title: String,
        value: Binding<Int>,
        leadingSystemImage: String = "minus.circle",
        trailingSystemImage: String = "plus.circle"
    ) -> SettingListGroup.Item {
        SettingListGroup.Item(
            id: id,
            title: title,
            accessory: .none,
            embeddedControl: .centerSlider(
                value: value,
                leadingSystemImage: leadingSystemImage,
                trailingSystemImage: trailingSystemImage,
                accessibilityLabel: title
            )
        )
    }

    private func restoreDefaults() {
        selectedSceneID = "day"
        selectedPositionID = "left"
        sceneAuto = true
        screenCurve = 0
        screenHeight = 0
        screenDistance = 0
        screenSize = 0
        threeDMode = false
        immersiveMode = .off
        hdrEnabled = false
        exposure = 0
        shadows = 0
        highlights = 0
        contrast = 0
        whites = 0
        temperature = 0
        tint = 0
        saturation = 0
        vibrance = 0
        sharpness = 0
    }
}

private struct PlayerSettingsPanelScrollFadeMask: View {
    var body: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .black, location: 0.08),
                .init(color: .black, location: 0.92),
                .init(color: .clear, location: 1),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

private enum PlayerPanelSettingsCategory: String, CaseIterable, Identifiable {
    case sceneSetting
    case playMode
    case advanced

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .sceneSetting:
            "Scene Setting"
        case .playMode:
            "Play Mode"
        case .advanced:
            "Advanced"
        }
    }

    var icon: String {
        switch self {
        case .sceneSetting:
            "mountain.2.fill"
        case .playMode:
            "play.rectangle"
        case .advanced:
            "slider.horizontal.3"
        }
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

// MARK: - Token pages

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

// MARK: - Token spec row (unified token display)

/// One token rendered as a single row: a visual `swatch`, its `leafName` and
/// `value`, and a usage `note`. Replaces the old "demo block + mono table"
/// split — the swatch and its data share one row, and the `DesignTokens.X.`
/// namespace prefix is shown once per section (on `TokenSpecSection`) instead
/// of repeated on every row.
struct TokenSpec: Identifiable {
    let id = UUID()
    let leafName: String
    let value: String
    let note: String
    let swatch: AnyView?

    /// A token with a visual representation (size, colour, shape, glyph).
    static func spec(
        _ leafName: String,
        _ value: String,
        _ note: String,
        @ViewBuilder swatch: () -> some View
    ) -> TokenSpec {
        TokenSpec(leafName: leafName, value: value, note: note, swatch: AnyView(swatch()))
    }

    /// A pure scalar/relationship token with no visual (e.g. `inactiveScale =
    /// 0.66`). The swatch column stays empty so rows stay aligned.
    static func scalar(_ leafName: String, _ value: String, _ note: String) -> TokenSpec {
        TokenSpec(leafName: leafName, value: value, note: note, swatch: nil)
    }
}

private struct TokenSpecRowView: View {
    let spec: TokenSpec
    let swatchWidth: CGFloat

    var body: some View {
        HStack(alignment: .center, spacing: DesignTokens.Spacing.md) {
            ZStack {
                if let swatch = spec.swatch {
                    swatch
                }
            }
            .frame(width: swatchWidth, height: swatchWidth)

            HStack(alignment: .firstTextBaseline, spacing: DesignTokens.Spacing.xs) {
                Text(spec.leafName)
                    .font(.system(.callout, design: .monospaced))
                Text(spec.value)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 200, alignment: .leading)

            Text(spec.note)
                .font(DesignTokens.Typography.metadata)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
        .padding(.vertical, DesignTokens.Spacing.sm)
        .frame(minHeight: swatchWidth + DesignTokens.Spacing.md, alignment: .center)
    }
}

/// A grouped, divider-separated list of token specs on the shared list-group
/// glass surface — the same visual language as `SettingListGroup`/`FileListGroup`.
struct TokenSpecGroup: View {
    let specs: [TokenSpec]
    var swatchWidth: CGFloat = 64

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(specs.enumerated()), id: \.element.id) { index, spec in
                if index > 0 {
                    SettingListGroupDivider()
                }
                TokenSpecRowView(spec: spec, swatchWidth: swatchWidth)
            }
        }
        .enchronListGroupSurface(cornerRadius: DesignTokens.Radius.element)
    }
}

/// A token section: an uppercase title with the namespace prefix shown once,
/// an optional `hero` demo (for tokens too large to fit a row swatch, e.g.
/// `playerControlsWidth`), and the spec group.
struct TokenSpecSection<Hero: View>: View {
    let title: String
    let namespace: String
    let specs: [TokenSpec]
    let hero: Hero

    init(
        title: String,
        namespace: String,
        specs: [TokenSpec],
        @ViewBuilder hero: () -> Hero = { EmptyView() }
    ) {
        self.title = title
        self.namespace = namespace
        self.specs = specs
        self.hero = hero()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            HStack(alignment: .firstTextBaseline, spacing: DesignTokens.Spacing.sm) {
                Text(title)
                    .font(DesignTokens.Typography.sectionHeader)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Text(namespace)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }

            if !(hero is EmptyView) {
                hero
                    .padding(.bottom, DesignTokens.Spacing.xs)
            }

            TokenSpecGroup(specs: specs)
        }
    }
}

// MARK: - Token swatches (reusable across token pages)

/// A filled accent circle of diameter `size`, nested inside a dashed reference
/// ring, so interactive/symbol sizes read at true scale against a common 64pt frame.
@ViewBuilder
private func tokenSizeSwatch(_ size: CGFloat, reference: CGFloat = 64) -> some View {
    ZStack {
        Circle()
            .stroke(style: StrokeStyle(lineWidth: DesignTokens.Stroke.regular, dash: [4, 3]))
            .foregroundStyle(.tertiary)
            .frame(width: reference, height: reference)
        Circle()
            .fill(Color.accentColor.opacity(0.2))
            .frame(width: min(size, reference), height: min(size, reference))
    }
}

/// A proportional accent bar — `value` mapped against `max` into a 56pt track.
@ViewBuilder
private func tokenBarSwatch(_ value: CGFloat, max maxValue: CGFloat, height: CGFloat = 16) -> some View {
    RoundedRectangle(cornerRadius: DesignTokens.Radius.small, style: .continuous)
        .fill(Color.accentColor.opacity(0.45))
        .frame(width: Swift.max(Swift.min(value / maxValue * 56, 56), 6), height: height)
}

/// A colour chip with a subtle border, for opacity/colour tokens.
@ViewBuilder
private func tokenColorSwatch(_ color: Color) -> some View {
    let shape = RoundedRectangle(cornerRadius: DesignTokens.Radius.small, style: .continuous)
    shape
        .fill(color)
        .frame(width: 40, height: 40)
        .overlay {
            shape.stroke(DesignTokens.Surface.divider, lineWidth: DesignTokens.Stroke.subtle)
        }
}

/// A filled rounded square showing a corner radius (capsule for `full`).
@ViewBuilder
private func tokenRadiusSwatch(_ radius: CGFloat) -> some View {
    if radius == .greatestFiniteMagnitude {
        let shape = Capsule()
        shape
            .fill(DesignTokens.Surface.elevated)
            .frame(width: 56, height: 36)
            .overlay { shape.strokeBorder(DesignTokens.Surface.border, lineWidth: DesignTokens.Stroke.regular) }
    } else {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        shape
            .fill(DesignTokens.Surface.elevated)
            .frame(width: 56, height: 56)
            .overlay { shape.strokeBorder(DesignTokens.Surface.border, lineWidth: DesignTokens.Stroke.regular) }
    }
}

/// A filled sample of a shape token.
@ViewBuilder
private func tokenShapeSwatch(_ shape: some Shape) -> some View {
    shape
        .fill(DesignTokens.Surface.elevated)
        .frame(width: 56, height: 56)
        .overlay { shape.stroke(DesignTokens.Surface.border, lineWidth: DesignTokens.Stroke.regular) }
}

/// A bordered rectangle drawn at a given stroke width.
@ViewBuilder
private func tokenStrokeSwatch(_ width: CGFloat) -> some View {
    RoundedRectangle(cornerRadius: DesignTokens.Radius.small, style: .continuous)
        .strokeBorder(Color.accentColor.opacity(0.75), lineWidth: width)
        .frame(width: 56, height: 44)
}

/// The glyph "Ag" set in a typography token, so weight/size read directly.
@ViewBuilder
private func tokenTypographySwatch(_ font: Font) -> some View {
    Text("Ag").font(font)
}

/// Two nested rectangles showing how far a press-feedback scale shrinks a shape.
@ViewBuilder
private func tokenScaleSwatch(_ scale: CGFloat) -> some View {
    let shape = RoundedRectangle(cornerRadius: DesignTokens.Radius.small, style: .continuous)
    ZStack {
        shape.stroke(DesignTokens.Surface.border, lineWidth: DesignTokens.Stroke.subtle)
            .frame(width: 48, height: 40)
        shape.fill(Color.accentColor.opacity(0.4))
            .frame(width: 48 * scale, height: 40 * scale)
    }
}

/// A small bar that animates open/closed on tap — a per-row "tap to replay"
/// sample for animation tokens.
private struct AnimationSampleSwatch: View {
    let name: String
    let animation: Animation
    @State private var expanded = false

    var body: some View {
        Button {
            withAnimation(animation) { expanded.toggle() }
        } label: {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.small, style: .continuous)
                .fill(expanded ? Color.accentColor.opacity(0.65) : DesignTokens.Surface.elevated)
                .frame(width: expanded ? 56 : 22, height: 22)
                .frame(width: 56, alignment: .leading)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("DesignPreview-Tokens-animation-\(name)")
        .accessibilityLabel("Replay \(name) animation")
    }
}

// MARK: - Spacing

struct SpacingScalePreview: View {
    private var specs: [TokenSpec] {
        [
            .spec("xxs", "4pt", "hover gap, micro adjustment") {
                tokenBarSwatch(DesignTokens.Spacing.xxs, max: 48, height: 20)
            },
            .spec("xs", "8pt", "compact padding, icon gaps") {
                tokenBarSwatch(DesignTokens.Spacing.xs, max: 48, height: 20)
            },
            .spec("sm", "12pt", "medium padding, list item spacing") {
                tokenBarSwatch(DesignTokens.Spacing.sm, max: 48, height: 20)
            },
            .spec("md", "16pt", "standard padding") {
                tokenBarSwatch(DesignTokens.Spacing.md, max: 48, height: 20)
            },
            .spec("lg", "20pt", "panel padding, section spacing") {
                tokenBarSwatch(DesignTokens.Spacing.lg, max: 48, height: 20)
            },
            .spec("xl", "24pt", "large gaps") {
                tokenBarSwatch(DesignTokens.Spacing.xl, max: 48, height: 20)
            },
            .spec("xxl", "32pt", "section dividers") {
                tokenBarSwatch(DesignTokens.Spacing.xxl, max: 48, height: 20)
            },
            .spec("xxxl", "48pt", "extra-large margins") {
                tokenBarSwatch(DesignTokens.Spacing.xxxl, max: 48, height: 20)
            },
        ]
    }

    var body: some View {
        TokenPage(title: "Spacing") {
            TokenSpecSection(
                title: "Spacing Scale",
                namespace: "DesignTokens.Spacing.*",
                specs: specs
            )
        }
    }
}

// MARK: - Radius & shapes

struct RadiusShapesPreview: View {
    private var radiusSpecs: [TokenSpec] {
        [
            .spec("panel", "40pt", "large panels, settings pages, detail views") {
                tokenRadiusSwatch(DesignTokens.Radius.panel)
            },
            .spec("card", "32pt", "cards, menus, mid-level containers") {
                tokenRadiusSwatch(DesignTokens.Radius.card)
            },
            .spec("element", "24pt", "menu items, toolbar, inner containers") {
                tokenRadiusSwatch(DesignTokens.Radius.element)
            },
            .spec("small", "12pt", "tags, thumbnails, small rounded backgrounds") {
                tokenRadiusSwatch(DesignTokens.Radius.small)
            },
            .spec("full", "full", "circles and capsules") {
                tokenRadiusSwatch(.greatestFiniteMagnitude)
            },
            .scalar("concentric", "function", "inner radius = outer radius − padding"),
        ]
    }

    private var shapeSpecs: [TokenSpec] {
        [
            .spec("panel", "radius 40", "large panel shape") {
                tokenShapeSwatch(DesignTokens.ShapeToken.panel)
            },
            .spec("card", "radius 32", "card and menu container shape") {
                tokenShapeSwatch(DesignTokens.ShapeToken.card)
            },
            .spec("element", "radius 24", "menu item and toolbar shape") {
                tokenShapeSwatch(DesignTokens.ShapeToken.element)
            },
        ]
    }

    private var concentricSpecs: [TokenSpec] {
        [
            .spec("panel → card", "40 − 8 = 32", "panel containing a card") {
                concentricSwatch(outer: DesignTokens.Radius.panel, inner: DesignTokens.Radius.card)
            },
            .spec("card → element", "32 − 8 = 24", "menu containing a row") {
                concentricSwatch(outer: DesignTokens.Radius.card, inner: DesignTokens.Radius.element)
            },
        ]
    }

    var body: some View {
        TokenPage(title: "Radius & Shapes") {
            TokenSpecSection(
                title: "Radius Tokens",
                namespace: "DesignTokens.Radius.*",
                specs: radiusSpecs
            )

            TokenSpecSection(
                title: "Shape Tokens",
                namespace: "DesignTokens.ShapeToken.*",
                specs: shapeSpecs
            )

            TokenSpecSection(
                title: "Concentric Examples",
                namespace: "outer − padding → inner",
                specs: concentricSpecs
            )
        }
    }

    @ViewBuilder
    private func concentricSwatch(outer: CGFloat, inner: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: outer, style: .continuous)
                .fill(DesignTokens.Surface.card)
                .frame(width: 60, height: 56)
            RoundedRectangle(cornerRadius: inner, style: .continuous)
                .fill(DesignTokens.Surface.overlay)
                .frame(width: 44, height: 40)
        }
    }
}

// MARK: - Interaction & layout

struct InteractionLayoutPreview: View {
    private var interactiveSpecs: [TokenSpec] {
        [
            .spec("mini", "28pt", "disclosure, auxiliary controls") {
                tokenSizeSwatch(DesignTokens.Interactive.mini)
            },
            .spec("compact", "36pt", "compact scrubbers and dense icon controls") {
                tokenSizeSwatch(DesignTokens.Interactive.compact)
            },
            .spec("regular", "44pt", "standard buttons") {
                tokenSizeSwatch(DesignTokens.Interactive.regular)
            },
            .spec("large", "60pt", "navigation buttons, self-sufficient target") {
                tokenSizeSwatch(DesignTokens.Interactive.large)
            },
            .spec("xl", "64pt", "primary action") {
                tokenSizeSwatch(DesignTokens.Interactive.xl)
            },
            .spec("rowHeight", "60pt", "menu/list row minimum height") {
                RoundedRectangle(cornerRadius: DesignTokens.Radius.small, style: .continuous)
                    .fill(Color.accentColor.opacity(0.18))
                    .frame(width: 52, height: 56)
            },
            .spec("buttonSpacing", "16pt", "minimum spacing between stacked buttons") {
                HStack(spacing: DesignTokens.Interactive.buttonSpacing) {
                    Circle().fill(Color.accentColor.opacity(0.25)).frame(width: 14, height: 14)
                    Circle().fill(Color.accentColor.opacity(0.25)).frame(width: 14, height: 14)
                }
            },
        ]
    }

    private var layoutSpecs: [TokenSpec] {
        [
            .spec("playerControlsWidth", "680pt", "PlayerControlsView and NLETimelineView panel width") {
                tokenBarSwatch(DesignTokens.Layout.playerControlsWidth, max: 680)
            },
            .spec("ornamentGap", "20pt", "ornament overlap with window bottom edge") {
                tokenBarSwatch(DesignTokens.Layout.ornamentGap, max: 680)
            },
        ]
    }

    private var progressBarSpecs: [TokenSpec] {
        [
            .spec("thumbDiameter", "24pt", "standard draggable scrubber button") {
                Circle()
                    .fill(.white)
                    .overlay {
                        Circle().strokeBorder(DesignTokens.Theme.accent, lineWidth: DesignTokens.Stroke.bold)
                    }
                    .frame(width: DesignTokens.ProgressBar.thumbDiameter, height: DesignTokens.ProgressBar.thumbDiameter)
            },
            .spec("trackHeight", "24pt", "active drag track height") {
                Capsule()
                    .fill(DesignTokens.Theme.accent)
                    .frame(width: 48, height: DesignTokens.ProgressBar.trackHeight)
            },
            .scalar("inactiveScale", "0.66", "unfocused and hover track height scale"),
            .spec("inactiveTrackHeight", "15.8pt", "track height before active drag") {
                Capsule()
                    .fill(DesignTokens.Theme.accent)
                    .frame(width: 48, height: DesignTokens.ProgressBar.inactiveTrackHeight)
            },
            .spec("hitHeight", "60pt", "hover and drag target height") {
                RoundedRectangle(cornerRadius: DesignTokens.Radius.small, style: .continuous)
                    .fill(Color.accentColor.opacity(0.18))
                    .frame(width: 28, height: 56)
            },
            .spec("previewWidth", "680pt", "Design Preview player progress width") {
                tokenBarSwatch(DesignTokens.ProgressBar.previewWidth, max: 680)
            },
            .scalar("timeBubbleOffset", "24pt", "time readout above scrubber"),
            .spec("playedColor", "white 0.72", "played portion in normal state") {
                tokenColorSwatch(.white.opacity(0.72))
            },
            .spec("unplayedColor", "white 0.16", "unplayed portion in normal state") {
                tokenColorSwatch(.white.opacity(0.16))
            },
        ]
    }

    var body: some View {
        TokenPage(title: "Interaction & Layout") {
            TokenSpecSection(
                title: "Interactive Sizes",
                namespace: "DesignTokens.Interactive.*",
                specs: interactiveSpecs
            )

            TokenSpecSection(
                title: "Layout Dimensions",
                namespace: "DesignTokens.Layout.*",
                specs: layoutSpecs
            ) {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
                    dimensionBar("playerControlsWidth", DesignTokens.Layout.playerControlsWidth, maxWidth: 680)
                    dimensionBar("ornamentGap", DesignTokens.Layout.ornamentGap, maxWidth: 220)
                }
            }

            TokenSpecSection(
                title: "Progress Bar",
                namespace: "DesignTokens.ProgressBar.*",
                specs: progressBarSpecs
            ) {
                PlayerControlDeck()
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
        }
    }
}

// MARK: - Typography & symbols

struct TypographySymbolsPreview: View {
    private var typographySpecs: [TokenSpec] {
        [
            .spec("title", ".title2", "video titles, page headings") {
                tokenTypographySwatch(DesignTokens.Typography.title)
            },
            .spec("headline", ".headline", "card titles, section labels") {
                tokenTypographySwatch(DesignTokens.Typography.headline)
            },
            .spec("metadata", ".caption", "resolution, file size, date metadata") {
                tokenTypographySwatch(DesignTokens.Typography.metadata)
            },
            .spec("sectionHeader", ".caption2", "section headers") {
                tokenTypographySwatch(DesignTokens.Typography.sectionHeader)
            },
            .spec("badge", ".caption", "badge labels") {
                Text("HDR")
                    .font(DesignTokens.Typography.badge)
                    .padding(.horizontal, DesignTokens.Spacing.xs)
                    .padding(.vertical, DesignTokens.Spacing.xxs)
                    .enchronGlassBadge()
            },
            .spec("monospacedDetail", "9pt medium mono", "timecode and ruler text") {
                Text("12:34")
                    .font(DesignTokens.Typography.monospacedDetail)
                    .foregroundStyle(.secondary)
            },
        ]
    }

    private var symbolSpecs: [TokenSpec] {
        [
            .spec("control", "24pt semibold", "skip and seek buttons") {
                symbolGlyph(DesignTokens.SymbolSize.control)
            },
            .spec("card", "36pt", "card and folder icons") {
                symbolGlyph(DesignTokens.SymbolSize.card)
            },
            .spec("action", "36pt medium", "play/pause primary action") {
                symbolGlyph(DesignTokens.SymbolSize.action)
            },
            .spec("feature", "44pt", "scene selector and large UI icons") {
                symbolGlyph(DesignTokens.SymbolSize.feature)
            },
            .spec("hero", "48pt", "hero detail view icons") {
                symbolGlyph(DesignTokens.SymbolSize.hero)
            },
            .spec("giant", "60pt", "empty state placeholder icons") {
                symbolGlyph(DesignTokens.SymbolSize.giant)
            },
        ]
    }

    var body: some View {
        TokenPage(title: "Typography & Symbols") {
            TokenSpecSection(
                title: "Typography",
                namespace: "DesignTokens.Typography.*",
                specs: typographySpecs
            )

            TokenSpecSection(
                title: "Symbol Sizes",
                namespace: "DesignTokens.SymbolSize.*",
                specs: symbolSpecs
            )
        }
    }

    private func symbolGlyph(_ font: Font) -> some View {
        Image(systemName: "play.fill")
            .font(font)
            .foregroundStyle(.secondary)
    }
}

// MARK: - Surface & stroke

struct SurfaceStrokePreview: View {
    private var surfaceSpecs: [TokenSpec] {
        [
            .spec("card", "white 0.03", "card background") {
                tokenColorSwatch(DesignTokens.Surface.card)
            },
            .spec("elevated", "white 0.04", "elevated panel background") {
                tokenColorSwatch(DesignTokens.Surface.elevated)
            },
            .spec("overlay", "white 0.06", "overlay / brighter surface") {
                tokenColorSwatch(DesignTokens.Surface.overlay)
            },
            .spec("selected", "white 0.08", "selected state background") {
                tokenColorSwatch(DesignTokens.Surface.selected)
            },
            .spec("border", "white 0.05", "subtle border") {
                tokenColorSwatch(DesignTokens.Surface.border)
            },
            .spec("focusBorder", "theme accent", "focused input/control border") {
                tokenColorSwatch(DesignTokens.Surface.focusBorder)
            },
        ]
    }

    private var strokeSpecs: [TokenSpec] {
        [
            .spec("subtle", "0.5pt", "card borders, unselected state") {
                tokenStrokeSwatch(DesignTokens.Stroke.subtle)
            },
            .spec("regular", "1.0pt", "timeline major ticks") {
                tokenStrokeSwatch(DesignTokens.Stroke.regular)
            },
            .spec("bold", "1.5pt", "playhead, selected state borders") {
                tokenStrokeSwatch(DesignTokens.Stroke.bold)
            },
        ]
    }

    var body: some View {
        TokenPage(title: "Surface & Stroke") {
            TokenSpecSection(
                title: "Surface Tiers",
                namespace: "DesignTokens.Surface.*",
                specs: surfaceSpecs
            )

            TokenSpecSection(
                title: "Stroke Widths",
                namespace: "DesignTokens.Stroke.*",
                specs: strokeSpecs
            )
        }
    }
}

// MARK: - Animation

struct AnimationTokensPreview: View {
    private var animationSpecs: [TokenSpec] {
        [
            .spec("controlsTransition", "easeInOut 0.4s", "controls show/hide") {
                AnimationSampleSwatch(name: "controlsTransition", animation: DesignTokens.AnimationToken.controlsTransition)
            },
            .spec("panelSpring", "spring 0.35 b0.15", "panel expand/collapse") {
                AnimationSampleSwatch(name: "panelSpring", animation: DesignTokens.AnimationToken.panelSpring)
            },
            .spec("menuPopup", "spring 0.35 b0.15", "menu/popover popup") {
                AnimationSampleSwatch(name: "menuPopup", animation: DesignTokens.AnimationToken.menuPopup)
            },
            .spec("selection", "bouncy 0.4 +0.1", "selection state change") {
                AnimationSampleSwatch(name: "selection", animation: DesignTokens.AnimationToken.selection)
            },
            .spec("playback", "spring r0.45 d0.85", "play/pause state") {
                AnimationSampleSwatch(name: "playback", animation: DesignTokens.AnimationToken.playback)
            },
            .spec("scene", "spring r0.3 d0.7", "cinema environment switch") {
                AnimationSampleSwatch(name: "scene", animation: DesignTokens.AnimationToken.scene)
            },
            .spec("fadeIn", "easeIn 0.25s", "content fade-in") {
                AnimationSampleSwatch(name: "fadeIn", animation: DesignTokens.AnimationToken.fadeIn)
            },
            .spec("skeleton", "easeInOut 1s repeat", "skeleton loading pulse") {
                AnimationSampleSwatch(name: "skeleton", animation: DesignTokens.AnimationToken.skeleton)
            },
        ]
    }

    private var spinnerSpecs: [TokenSpec] {
        [
            .scalar("headAnimation", "easeOut 0.7s", "spinner head extension"),
            .scalar("tailAnimation", "easeOut 0.55s", "spinner tail catch-up"),
            .scalar("headDuration", "700ms", "spinner head phase duration"),
            .scalar("tailDuration", "550ms", "spinner tail phase duration"),
        ]
    }

    var body: some View {
        TokenPage(title: "Animation") {
            TokenSpecSection(
                title: "Animation Tokens",
                namespace: "DesignTokens.AnimationToken.*  ·  tap to replay",
                specs: animationSpecs
            )

            TokenSpecSection(
                title: "Loading Spinner",
                namespace: "DesignTokens.LoadingSpinner.*",
                specs: spinnerSpecs
            ) {
                LoadingSpinner()
            }
        }
    }
}

// MARK: - Press feedback

struct PressFeedbackPreview: View {
    private var specs: [TokenSpec] {
        [
            .spec("card", "scale 0.97", "cards and broad spatial surfaces") {
                tokenScaleSwatch(DesignTokens.PressFeedback.card.pressedScale)
            },
            .spec("row", "scale 0.985", "menu rows and list items") {
                tokenScaleSwatch(DesignTokens.PressFeedback.row.pressedScale)
            },
            .spec("control", "scale 0.96", "control capsules and grouped controls") {
                tokenScaleSwatch(DesignTokens.PressFeedback.control.pressedScale)
            },
            .spec("icon", "scale 0.90", "individual icon targets, stronger return spring") {
                tokenScaleSwatch(DesignTokens.PressFeedback.icon.pressedScale)
            },
        ]
    }

    var body: some View {
        TokenPage(title: "Press Feedback") {
            TokenSpecSection(
                title: "Press Feedback Tokens",
                namespace: "DesignTokens.PressFeedback.*  ·  tap a shape to feel it",
                specs: specs
            ) {
                HStack(alignment: .center, spacing: DesignTokens.Spacing.xl) {
                    pressCardPreview
                    pressRowPreview
                    pressControlPreview
                    pressIconPreview
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

    private func scaleText(_ spec: DesignTokens.PressFeedbackSpec) -> String {
        String(format: "%.3f", spec.pressedScale)
    }
}

// MARK: - Component standards

struct ComponentStandardsPreview: View {
    private var cardSpecs: [TokenSpec] {
        [
            .spec("paddingH", "16pt", "horizontal padding inside card text area") {
                tokenBarSwatch(DesignTokens.Card.paddingH, max: 48)
            },
            .spec("paddingV", "14pt", "vertical padding inside card text area") {
                tokenBarSwatch(DesignTokens.Card.paddingV, max: 48)
            },
            .spec("gridMin", "224pt", "adaptive grid minimum card width") {
                tokenBarSwatch(DesignTokens.Card.gridMin, max: 224)
            },
            .spec("thumbnailHeight", "140pt", "thumbnail height for grid cards") {
                tokenBarSwatch(DesignTokens.Card.thumbnailHeight, max: 224)
            },
            .spec("gridSpacing", "20pt", "grid inter-item spacing") {
                tokenBarSwatch(DesignTokens.Card.gridSpacing, max: 224)
            },
        ]
    }

    private var controlSpecs: [TokenSpec] {
        [
            .spec("width", "680pt", "matches Layout.playerControlsWidth") {
                tokenBarSwatch(DesignTokens.ControlBar.width, max: 680)
            },
            .spec("buttonSpacing", "24pt", "spacing between playback controls") {
                tokenBarSwatch(DesignTokens.ControlBar.buttonSpacing, max: 48)
            },
            .spec("paddingH", "32pt", "horizontal padding inside control capsule") {
                tokenBarSwatch(DesignTokens.ControlBar.paddingH, max: 48)
            },
            .spec("paddingV", "12pt", "vertical padding inside control capsule") {
                tokenBarSwatch(DesignTokens.ControlBar.paddingV, max: 48)
            },
            .spec("primaryFill", "white 0.72", "primary play button fill") {
                tokenColorSwatch(.white.opacity(0.72))
            },
            .spec("primarySymbol", "black 0.78", "primary play symbol color") {
                tokenColorSwatch(.black.opacity(0.78))
            },
        ]
    }

    var body: some View {
        TokenPage(title: "Component Standards") {
            TokenSpecSection(
                title: "Card",
                namespace: "DesignTokens.Card.*",
                specs: cardSpecs
            ) {
                VideoCardLarge(title: "Interstellar", fileSize: "8.2 GB", duration: "2:49:00", badges: ["HDR10+"])
            }

            TokenSpecSection(
                title: "Control Bar",
                namespace: "DesignTokens.ControlBar.*",
                specs: controlSpecs
            ) {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
                    dimensionBar("width", DesignTokens.ControlBar.width, maxWidth: 360)
                    PlayerControlDeck()
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
