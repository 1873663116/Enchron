import DesignSystem
import PlaybackFeature
import PlaybackPresentation
import SwiftUI

enum PlaybackTopSecondaryMenu: String {
    case dock
    case videoFormat
}

struct PlaybackVideoFormatSelection: Equatable {
    let projection: PlaybackModel.ProjectionType
    let stereoLayout: PlaybackModel.StereoLayout
}

enum PlaybackVideoFormatEditingDecision {
    case cancel
    case apply
}

struct PlaybackTopActionsState {
    var presentedMenu: PlaybackTopSecondaryMenu?
    var selectedDockEnvironment: SpatialSceneDomain.CinemaEnvironment
    var selectedEffect: SpatialSceneDomain.EnvironmentEffect?
    var projection: PlaybackModel.ProjectionType
    var stereoLayout: PlaybackModel.StereoLayout

    private var selectionBeforeEditing: PlaybackVideoFormatSelection

    init(
        presentedMenu: PlaybackTopSecondaryMenu? = nil,
        selectedDockEnvironment: SpatialSceneDomain.CinemaEnvironment = .defaultScenic,
        selectedEffect: SpatialSceneDomain.EnvironmentEffect? = .night,
        projection: PlaybackModel.ProjectionType = .equirectangular180,
        stereoLayout: PlaybackModel.StereoLayout = .mono
    ) {
        self.presentedMenu = presentedMenu
        self.selectedDockEnvironment = selectedDockEnvironment
        self.selectedEffect = selectedEffect
        self.projection = projection
        self.stereoLayout = stereoLayout
        self.selectionBeforeEditing = PlaybackVideoFormatSelection(
            projection: projection,
            stereoLayout: stereoLayout
        )
    }

    mutating func toggleMenu(_ menu: PlaybackTopSecondaryMenu) {
        if presentedMenu == menu {
            dismissMenu()
            return
        }

        if presentedMenu == .videoFormat {
            discardVideoFormatChanges()
        }
        if menu == .videoFormat {
            selectionBeforeEditing = currentVideoFormatSelection
        }
        presentedMenu = menu
    }

    mutating func dismissMenu() {
        if presentedMenu == .videoFormat {
            discardVideoFormatChanges()
        }
        presentedMenu = nil
    }

    mutating func finishVideoFormatEditing(
        _ decision: PlaybackVideoFormatEditingDecision
    ) -> PlaybackVideoFormatSelection? {
        guard presentedMenu == .videoFormat else { return nil }
        presentedMenu = nil
        switch decision {
        case .cancel:
            discardVideoFormatChanges()
            return nil
        case .apply:
            let selection = currentVideoFormatSelection
            selectionBeforeEditing = selection
            return selection
        }
    }

    mutating func selectDockTarget(
        environment: SpatialSceneDomain.CinemaEnvironment,
        effect: SpatialSceneDomain.EnvironmentEffect?
    ) -> (SpatialSceneDomain.CinemaEnvironment, SpatialSceneDomain.EnvironmentEffect?) {
        selectedDockEnvironment = environment
        selectedEffect = effect
        presentedMenu = nil
        return (environment, effect)
    }

    private var currentVideoFormatSelection: PlaybackVideoFormatSelection {
        PlaybackVideoFormatSelection(
            projection: projection,
            stereoLayout: stereoLayout
        )
    }

    private mutating func discardVideoFormatChanges() {
        projection = selectionBeforeEditing.projection
        stereoLayout = selectionBeforeEditing.stereoLayout
    }
}

struct PlaybackTopActions: View {
    private let canDock: Bool
    private let canApplyFormat: Bool
    private let canUseFisheye: Bool
    private let resumesPanorama: Bool
    private let defaultScenicEnvironment: SpatialSceneDomain.CinemaEnvironment
    private let onDock: ((SpatialSceneDomain.CinemaEnvironment, SpatialSceneDomain.EnvironmentEffect?) -> Void)?
    private let onApplyFormat: ((PlaybackModel.ProjectionType, PlaybackModel.StereoLayout) -> Void)?
    private let onResumePanorama: (() -> Void)?

    @State private var state: PlaybackTopActionsState

    init(
        initialPresentedMenu: PlaybackTopSecondaryMenu? = nil,
        canDock: Bool = true,
        canApplyFormat: Bool = true,
        canUseFisheye: Bool = false,
        resumesPanorama: Bool = false,
        defaultScenicEnvironment: SpatialSceneDomain.CinemaEnvironment = .defaultScenic,
        onDock: ((SpatialSceneDomain.CinemaEnvironment, SpatialSceneDomain.EnvironmentEffect?) -> Void)? = nil,
        onApplyFormat: ((PlaybackModel.ProjectionType, PlaybackModel.StereoLayout) -> Void)? = nil,
        onResumePanorama: (() -> Void)? = nil
    ) {
        self.canDock = canDock
        self.canApplyFormat = canApplyFormat
        self.canUseFisheye = canUseFisheye
        self.resumesPanorama = resumesPanorama
        self.defaultScenicEnvironment = defaultScenicEnvironment.isScenic
            ? defaultScenicEnvironment
            : .defaultScenic
        self.onDock = onDock
        self.onApplyFormat = onApplyFormat
        self.onResumePanorama = onResumePanorama
        _state = State(
                initialValue: PlaybackTopActionsState(
                    presentedMenu: initialPresentedMenu,
                    selectedDockEnvironment: defaultScenicEnvironment
                )
        )
    }

    var body: some View {
        ZStack(alignment: .top) {
            topButtonRow

            if state.presentedMenu == .dock {
                dockMenu
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .offset(y: secondaryMenuTopOffset)
                    .zIndex(10)
            }

            if state.presentedMenu == .videoFormat {
                videoFormatMenu
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .offset(y: secondaryMenuTopOffset)
                    .zIndex(10)
            }
        }
        // The menu area always has real bounds, so its controls remain hittable,
        // while the button row keeps the same identity and geometry across menu
        // presentation changes. Empty ZStack space has no hit shape of its own.
        .frame(height: 420, alignment: .top)
        .onChange(of: canApplyFormat) { _, available in
            if available == false, state.presentedMenu == .videoFormat { dismissMenu() }
        }
    }

    private var secondaryMenuTopOffset: CGFloat {
        DesignTokens.Interactive.large + DesignTokens.Spacing.sm
    }

    private var topButtonRow: some View {
        WindowPlaybackSpatialActions {
            if canDock {
                PlaybackTopSecondaryPanelButton(
                    systemName: "mountain.2.fill",
                    accessibilityLabel: "Dock",
                    action: { toggle(.dock) },
                    accessibilityIdentifier: "PlayerUI-TopAction-dock",
                    iconTier: .compact
                )
            }
        } formatControl: {
            if resumesPanorama {
                GlassCircleIconButton.expandVertically(
                    accessibilityLabel: "Return to Panorama",
                    action: { onResumePanorama?() },
                    accessibilityIdentifier: "PlayerUI-TopAction-resumePanorama"
                )
            } else {
                PlaybackTopSecondaryPanelButton(
                    systemName: "rectangle.arrowtriangle.2.outward",
                    accessibilityLabel: "Video Format",
                    action: { toggle(.videoFormat) },
                    accessibilityIdentifier: "PlayerUI-TopAction-videoFormat"
                )
                .disabled(!canApplyFormat)
            }
        }
    }

    private var dockMenu: some View {
        let shape = RoundedRectangle(
            cornerRadius: DesignTokens.Radius.card,
            style: .continuous
        )

        return VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Text("View in \(defaultScenicEnvironment.displayName)")
                .font(DesignTokens.Typography.metadata)
                .foregroundStyle(.secondary)
                .padding(.horizontal, DesignTokens.Spacing.sm)

            dockMenuItem(
                environment: defaultScenicEnvironment,
                effect: .night,
                thumbnailName: dockThumbnailName(for: .night)
            )
            dockMenuItem(
                environment: defaultScenicEnvironment,
                effect: .day,
                thumbnailName: dockThumbnailName(for: .day)
            )

            Divider()
                .padding(.vertical, DesignTokens.Spacing.xs)

            dockMenuItem(
                environment: .skybox,
                effect: nil,
                thumbnailName: "SceneFeatureCinema"
            )
        }
        .padding(DesignTokens.Spacing.md)
        .frame(width: 360)
        .fixedSize(horizontal: false, vertical: true)
        .contentShape(shape)
        .clipShape(shape)
        .enchronGlassBackground(in: shape)
        .onTapGesture { }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("PlayerUI-DockMenu")
    }

    private func dockThumbnailName(
        for effect: SpatialSceneDomain.EnvironmentEffect
    ) -> String {
        FeaturedEnvironment.catalogEntry(for: defaultScenicEnvironment)?
            .imageName(for: effect)
            ?? FeaturedEnvironment.catalog[0].imageName(for: effect)
    }

    private func dockMenuItem(
        environment: SpatialSceneDomain.CinemaEnvironment,
        effect: SpatialSceneDomain.EnvironmentEffect?,
        thumbnailName: String
    ) -> some View {
        Button {
            let requested = state.selectDockTarget(
                environment: environment,
                effect: effect
            )
            onDock?(requested.0, requested.1)
        } label: {
            HStack(spacing: DesignTokens.Spacing.md) {
                Image(thumbnailName)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 48, height: 48)
                    .clipped()
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(environment.displayName)
                        .font(DesignTokens.Typography.selectionHeader)
                    if let effect {
                        Text(effect == .night ? "Dark" : "Light")
                            .font(DesignTokens.Typography.metadata)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, DesignTokens.Spacing.sm)
            .frame(maxWidth: .infinity, minHeight: 68, alignment: .leading)
            .background {
                if state.selectedDockEnvironment == environment,
                   state.selectedEffect == effect {
                    RoundedRectangle(
                        cornerRadius: DesignTokens.Radius.element,
                        style: .continuous
                    )
                    .fill(DesignTokens.Surface.selected)
                }
            }
            .contentShape(
                RoundedRectangle(
                    cornerRadius: DesignTokens.Radius.element,
                    style: .continuous
                )
            )
        }
        .buttonStyle(.plain)
        .enchronHoverContentShape(
            RoundedRectangle(
                cornerRadius: DesignTokens.Radius.element,
                style: .continuous
            )
        )
        .enchronHoverEffect(.automatic)
        .accessibilityLabel(
            effect.map { "\(environment.displayName), \($0 == .night ? "Dark" : "Light")" }
                ?? environment.displayName
        )
        .accessibilityIdentifier(
            effect.map { "PlayerUI-DockMenu-\($0.rawValue)" }
                ?? "PlayerUI-DockMenu-skybox"
        )
        .accessibilityAddTraits(
            state.selectedDockEnvironment == environment
                && state.selectedEffect == effect ? .isSelected : []
        )
    }

    private func toggle(_ menu: PlaybackTopSecondaryMenu) {
        state.toggleMenu(menu)
    }

    private func dismissMenu() {
        state.dismissMenu()
    }

    private func cancelVideoFormat() {
        _ = state.finishVideoFormatEditing(.cancel)
    }

    private func applyVideoFormat() {
        guard let selection = state.finishVideoFormatEditing(.apply) else { return }
        onApplyFormat?(selection.projection, selection.stereoLayout)
    }

    private var videoFormatMenu: some View {
        let shape = RoundedRectangle(
            cornerRadius: DesignTokens.Radius.card,
            style: .continuous
        )

        return VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
            menuHeading("Video Format", supporting: "Choose how the video is presented")

            formatPicker(
                title: "Projection",
                selection: $state.projection,
                options: [
                    PlaybackModel.ProjectionType.equirectangular180,
                    .equirectangular360
                ] + (canUseFisheye ? [.fisheye] : []),
                label: projectionTitle
            )

            formatPicker(
                title: "Stereo Layout",
                selection: $state.stereoLayout,
                options: PlaybackModel.StereoLayout.allCases,
                label: stereoTitle
            )

            HStack {
                Spacer()
                Button("Cancel") {
                    cancelVideoFormat()
                }
                .accessibilityIdentifier("PlayerUI-VideoFormat-cancel")
                Button("Apply") {
                    applyVideoFormat()
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("PlayerUI-VideoFormat-apply")
            }
        }
        .padding(DesignTokens.Spacing.lg)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
        .contentShape(shape)
        .clipShape(shape)
        .enchronGlassBackground(in: shape)
        .onTapGesture { }
    }

    private func menuHeading(_ title: String, supporting: String) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            Text(title)
                .font(DesignTokens.Typography.headline)
            Text(supporting)
                .font(DesignTokens.Typography.metadata)
                .foregroundStyle(.secondary)
        }
    }

    private func formatPicker<Value: Hashable>(
        title: String,
        selection: Binding<Value>,
        options: [Value],
        label: @escaping (Value) -> String
    ) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Text(title)
                .font(DesignTokens.Typography.metadata)
                .foregroundStyle(.secondary)
            Picker(title, selection: selection) {
                ForEach(options, id: \.self) { option in
                    Text(label(option))
                        .tag(option)
                        .accessibilityIdentifier("PlayerUI-VideoFormat-\(title)-\(label(option))")
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityLabel(title)
        }
    }

    private func projectionTitle(_ projection: PlaybackModel.ProjectionType) -> String {
        switch projection {
        case .flat: "Flat"
        case .equirectangular180: "180°"
        case .equirectangular360: "360°"
        case .fisheye: "Fisheye"
        }
    }

    private func stereoTitle(_ stereoLayout: PlaybackModel.StereoLayout) -> String {
        switch stereoLayout {
        case .mono: "Mono"
        case .sideBySide: "Side-by-Side"
        case .topBottom: "Top-Bottom"
        }
    }
}

/// Opens an inline panel in the same SwiftUI tree. The glass label owns hover
/// feedback, while the outer button remains plain so inserting the panel does
/// not interrupt an in-flight scale animation on the label's glass layer.
private struct PlaybackTopSecondaryPanelButton: View {
    let systemName: String
    let accessibilityLabel: String
    let action: () -> Void
    let accessibilityIdentifier: String
    var iconTier: ButtonIconTier = .standard

    var body: some View {
        Button(action: action) {
            GlassCircleIconLabel(
                systemName: systemName,
                accessibilityLabel: accessibilityLabel,
                iconTier: iconTier
            )
            .accessibilityHidden(true)
            .frame(
                width: DesignTokens.Interactive.large,
                height: DesignTokens.Interactive.large
            )
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .contentShape(Circle())
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}
