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
    let horizontalFieldOfViewDegrees: Int?
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
    var horizontalFieldOfViewDegrees: Int
    var stereoLayout: PlaybackModel.StereoLayout

    private var selectionBeforeEditing: PlaybackVideoFormatSelection

    init(
        presentedMenu: PlaybackTopSecondaryMenu? = nil,
        selectedDockEnvironment: SpatialSceneDomain.CinemaEnvironment = .defaultScenic,
        selectedEffect: SpatialSceneDomain.EnvironmentEffect? = .dark,
        projection: PlaybackModel.ProjectionType = .flat,
        horizontalFieldOfViewDegrees: Int = PanoramaHorizontalCoverage.defaultCustomAngle,
        stereoLayout: PlaybackModel.StereoLayout = .mono
    ) {
        self.presentedMenu = presentedMenu
        self.selectedDockEnvironment = selectedDockEnvironment
        self.selectedEffect = selectedEffect
        self.projection = projection
        self.horizontalFieldOfViewDegrees = horizontalFieldOfViewDegrees
        self.stereoLayout = stereoLayout
        self.selectionBeforeEditing = PlaybackVideoFormatSelection(
            projection: projection,
            horizontalFieldOfViewDegrees: horizontalFieldOfViewDegrees,
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

    mutating func synchronizeCommittedVideoFormat(
        _ selection: PlaybackVideoFormatSelection
    ) {
        guard presentedMenu != .videoFormat else { return }
        projection = selection.projection
        horizontalFieldOfViewDegrees = selection.horizontalFieldOfViewDegrees
            ?? PanoramaHorizontalCoverage.defaultCustomAngle
        stereoLayout = selection.stereoLayout
        selectionBeforeEditing = selection
    }

    mutating func restoreAutomaticFormat() -> Bool {
        guard presentedMenu == .videoFormat else { return false }
        dismissMenu()
        return true
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
            horizontalFieldOfViewDegrees: projection == .customAngle
                ? horizontalFieldOfViewDegrees
                : nil,
            stereoLayout: stereoLayout
        )
    }

    private mutating func discardVideoFormatChanges() {
        projection = selectionBeforeEditing.projection
        horizontalFieldOfViewDegrees = selectionBeforeEditing.horizontalFieldOfViewDegrees
            ?? PanoramaHorizontalCoverage.defaultCustomAngle
        stereoLayout = selectionBeforeEditing.stereoLayout
    }
}

struct PlaybackTopActions: View {
    private let canDock: Bool
    private let canApplyFormat: Bool
    private let resumesPanorama: Bool
    private let mediaFormatProvenance: MediaFormatProvenance
    private let sourceMediaFormatSummary: String
    private let committedProjection: PlaybackModel.ProjectionType
    private let committedHorizontalFieldOfViewDegrees: Int
    private let committedStereoLayout: PlaybackModel.StereoLayout
    private let defaultScenicEnvironment: SpatialSceneDomain.CinemaEnvironment
    private let onDock: ((SpatialSceneDomain.CinemaEnvironment, SpatialSceneDomain.EnvironmentEffect?) -> Void)?
    private let onApplyFormat: ((PlaybackModel.ProjectionType, Int?, PlaybackModel.StereoLayout) -> Void)?
    private let onRestoreAutomaticFormat: (() -> Void)?
    private let onResumePanorama: (() -> Void)?
    private let onSecondaryMenuVisibilityChange: ((Bool) -> Void)?

    @State private var state: PlaybackTopActionsState

    init(
        initialPresentedMenu: PlaybackTopSecondaryMenu? = nil,
        canDock: Bool = true,
        canApplyFormat: Bool = true,
        resumesPanorama: Bool = false,
        mediaFormatProvenance: MediaFormatProvenance = .source,
        sourceMediaFormatSummary: String = "Flat · Mono",
        projection: PlaybackModel.ProjectionType = .flat,
        horizontalFieldOfViewDegrees: Int = PanoramaHorizontalCoverage.defaultCustomAngle,
        stereoLayout: PlaybackModel.StereoLayout = .mono,
        defaultScenicEnvironment: SpatialSceneDomain.CinemaEnvironment = .defaultScenic,
        onDock: ((SpatialSceneDomain.CinemaEnvironment, SpatialSceneDomain.EnvironmentEffect?) -> Void)? = nil,
        onApplyFormat: ((PlaybackModel.ProjectionType, Int?, PlaybackModel.StereoLayout) -> Void)? = nil,
        onRestoreAutomaticFormat: (() -> Void)? = nil,
        onResumePanorama: (() -> Void)? = nil,
        onSecondaryMenuVisibilityChange: ((Bool) -> Void)? = nil
    ) {
        self.canDock = canDock
        self.canApplyFormat = canApplyFormat
        self.resumesPanorama = resumesPanorama
        self.mediaFormatProvenance = mediaFormatProvenance
        self.sourceMediaFormatSummary = sourceMediaFormatSummary
        self.committedProjection = projection
        self.committedHorizontalFieldOfViewDegrees = horizontalFieldOfViewDegrees
        self.committedStereoLayout = stereoLayout
        self.defaultScenicEnvironment = defaultScenicEnvironment.isScenic
            ? defaultScenicEnvironment
            : .defaultScenic
        self.onDock = onDock
        self.onApplyFormat = onApplyFormat
        self.onRestoreAutomaticFormat = onRestoreAutomaticFormat
        self.onResumePanorama = onResumePanorama
        self.onSecondaryMenuVisibilityChange = onSecondaryMenuVisibilityChange
        _state = State(
                initialValue: PlaybackTopActionsState(
                    presentedMenu: initialPresentedMenu,
                    selectedDockEnvironment: defaultScenicEnvironment,
                    projection: projection,
                    horizontalFieldOfViewDegrees: horizontalFieldOfViewDegrees,
                    stereoLayout: stereoLayout
                )
        )
    }

    var body: some View {
        ZStack(alignment: .top) {
            topButtonRow

            if state.presentedMenu == .dock {
                dockMenu
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, secondaryMenuTopOffset)
                    .zIndex(10)
            }

            if state.presentedMenu == .videoFormat {
                videoFormatMenu
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.top, secondaryMenuTopOffset)
                    .zIndex(10)
            }
        }
        // Secondary menus use layout padding instead of a visual offset so their
        // Accessibility frames remain inside this stable top-chrome region.
        // Empty ZStack space has no hit shape of its own.
        .frame(height: 420, alignment: .top)
        .onAppear {
            onSecondaryMenuVisibilityChange?(state.presentedMenu != nil)
        }
        .onDisappear {
            onSecondaryMenuVisibilityChange?(false)
        }
        .onChange(of: state.presentedMenu) { _, menu in
            onSecondaryMenuVisibilityChange?(menu != nil)
        }
        .onChange(of: canApplyFormat) { _, available in
            if available == false, state.presentedMenu == .videoFormat { dismissMenu() }
        }
        .onChange(of: committedVideoFormatSelection) { _, selection in
            state.synchronizeCommittedVideoFormat(selection)
        }
    }

    private var secondaryMenuTopOffset: CGFloat {
        DesignTokens.Interactive.large + DesignTokens.Spacing.sm
    }

    private var topButtonRow: some View {
        WindowPlaybackSpatialActions {
            if resumesPanorama {
                GlassCircleIconButton.expandVertically(
                    accessibilityLabel: "Return to Panorama",
                    action: { onResumePanorama?() },
                    accessibilityIdentifier: "PlayerUI-TopAction-resumePanorama"
                )
            } else if canDock {
                PlaybackTopSecondaryPanelButton(
                    systemName: "mountain.2.fill",
                    accessibilityLabel: "Dock",
                    action: { toggle(.dock) },
                    accessibilityIdentifier: "PlayerUI-TopAction-dock",
                    iconTier: .compact
                )
            }
        } formatControl: {
            if resumesPanorama == false {
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
                effect: .dark,
                thumbnailName: dockThumbnailName(for: .dark)
            )
            dockMenuItem(
                environment: defaultScenicEnvironment,
                effect: .light,
                thumbnailName: dockThumbnailName(for: .light)
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
        .background {
            secondaryMenuInteractionShield(shape)
        }
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
        let shape = RoundedRectangle(
            cornerRadius: DesignTokens.Radius.element,
            style: .continuous
        )

        return Button {
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
                        Text(effect == .dark ? "Dark Mode" : "Light Mode")
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
            .contentShape(.interaction, shape)
        }
        .buttonStyle(.plain)
        .contentShape(.interaction, shape)
        .enchronHoverContentShape(shape)
        .enchronHoverEffect(.automatic)
        .accessibilityLabel(
            effect.map {
                "\(environment.displayName), \($0 == .dark ? "Dark Mode" : "Light Mode")"
            }
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
        // The runtime remains authoritative until the async core operation
        // succeeds. This also restores the visible committed value if it fails.
        state.synchronizeCommittedVideoFormat(committedVideoFormatSelection)
        onApplyFormat?(
            selection.projection,
            selection.horizontalFieldOfViewDegrees,
            selection.stereoLayout
        )
    }

    private func restoreAutomaticFormat() {
        guard state.restoreAutomaticFormat() else { return }
        onRestoreAutomaticFormat?()
    }

    private var committedVideoFormatSelection: PlaybackVideoFormatSelection {
        PlaybackVideoFormatSelection(
            projection: committedProjection,
            horizontalFieldOfViewDegrees: committedProjection == .customAngle
                ? committedHorizontalFieldOfViewDegrees
                : nil,
            stereoLayout: committedStereoLayout
        )
    }

    private var videoFormatMenu: some View {
        let shape = RoundedRectangle(
            cornerRadius: DesignTokens.Radius.card,
            style: .continuous
        )

        return VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
            menuHeading("Video Format", supporting: "Choose how the video is presented")

            Button {
                restoreAutomaticFormat()
            } label: {
                HStack(spacing: DesignTokens.Spacing.md) {
                    Image(systemName: mediaFormatProvenance == .source
                        ? "checkmark.circle.fill"
                        : "arrow.uturn.backward.circle")
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Automatic")
                            .font(DesignTokens.Typography.selectionHeader)
                        Text(sourceMediaFormatSummary)
                            .font(DesignTokens.Typography.metadata)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .disabled(mediaFormatProvenance == .source || !canApplyFormat)
            .accessibilityIdentifier("PlayerUI-VideoFormat-automatic")

            Divider()

            formatPicker(
                title: "Projection",
                selection: $state.projection,
                options: [
                    PlaybackModel.ProjectionType.flat,
                    PlaybackModel.ProjectionType.equirectangular180,
                    .equirectangular360
                ],
                label: projectionTitle
            )

            Menu {
                ForEach(PanoramaHorizontalCoverage.selectableAngles, id: \.self) { degrees in
                    Button("\(degrees)°") {
                        state.projection = .customAngle
                        state.horizontalFieldOfViewDegrees = degrees
                    }
                }
            } label: {
                Label(
                    state.projection == .customAngle
                        ? "Custom Angle · \(state.horizontalFieldOfViewDegrees)°"
                        : "Custom Angle",
                    systemImage: "angle"
                )
            }
            .accessibilityIdentifier("PlayerUI-VideoFormat-CustomAngle")

            formatPicker(
                title: "Stereo Layout",
                selection: $state.stereoLayout,
                options: PlaybackModel.StereoLayout.userSelectableCases,
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
        .background {
            secondaryMenuInteractionShield(shape)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("PlayerUI-VideoFormat")
    }

    private func secondaryMenuInteractionShield<S: Shape>(_ shape: S) -> some View {
        Color.clear
            .contentShape(.interaction, shape)
            .onTapGesture { }
            .accessibilityHidden(true)
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
        case .customAngle: "Custom Angle"
        }
    }

    private func stereoTitle(_ stereoLayout: PlaybackModel.StereoLayout) -> String {
        switch stereoLayout {
        case .mono: "Mono"
        case .multiview: "Native Multiview"
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
