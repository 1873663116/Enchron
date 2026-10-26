import DesignSystem
import OSLog
import SwiftUI

public enum PlaybackTopSecondaryMenu: String {
    case dock
    case videoFormat
}

struct PlaybackTopActionsComposition: Equatable {
    let showsPanoramaEntry: Bool
    let showsDock: Bool
    let showsVideoFormat: Bool

    init(immersiveEntryTarget: PlaybackPresentation?) {
        showsPanoramaEntry = immersiveEntryTarget == .panorama
        showsDock = immersiveEntryTarget == .docked
        showsVideoFormat = true
    }
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

struct PlaybackVideoFormatEditingState {
    var projection: PlaybackModel.ProjectionType
    var horizontalFieldOfViewDegrees: Int
    var stereoLayout: PlaybackModel.StereoLayout

    private var selectionBeforeEditing: PlaybackVideoFormatSelection
    private var isEditing: Bool

    init(
        projection: PlaybackModel.ProjectionType = .flat,
        horizontalFieldOfViewDegrees: Int = PanoramaHorizontalCoverage.defaultCustomAngle,
        stereoLayout: PlaybackModel.StereoLayout = .mono,
        beginsEditing: Bool = false
    ) {
        self.projection = projection
        self.horizontalFieldOfViewDegrees = horizontalFieldOfViewDegrees
        self.stereoLayout = stereoLayout
        self.selectionBeforeEditing = PlaybackVideoFormatSelection(
            projection: projection,
            horizontalFieldOfViewDegrees: horizontalFieldOfViewDegrees,
            stereoLayout: stereoLayout
        )
        self.isEditing = beginsEditing
    }

    mutating func beginEditing() {
        selectionBeforeEditing = currentSelection
        isEditing = true
    }

    mutating func commit() -> PlaybackVideoFormatSelection? {
        guard isEditing else { return nil }
        let selection = currentSelection
        selectionBeforeEditing = selection
        isEditing = false
        return selection
    }

    mutating func discard() {
        guard isEditing else { return }
        projection = selectionBeforeEditing.projection
        horizontalFieldOfViewDegrees = selectionBeforeEditing.horizontalFieldOfViewDegrees
            ?? PanoramaHorizontalCoverage.defaultCustomAngle
        stereoLayout = selectionBeforeEditing.stereoLayout
        isEditing = false
    }

    mutating func synchronizeCommittedVideoFormat(
        _ selection: PlaybackVideoFormatSelection
    ) {
        guard isEditing == false else { return }
        projection = selection.projection
        horizontalFieldOfViewDegrees = selection.horizontalFieldOfViewDegrees
            ?? PanoramaHorizontalCoverage.defaultCustomAngle
        stereoLayout = selection.stereoLayout
        selectionBeforeEditing = selection
    }

    private var currentSelection: PlaybackVideoFormatSelection {
        PlaybackVideoFormatSelection(
            projection: projection,
            horizontalFieldOfViewDegrees: projection == .customAngle
                ? horizontalFieldOfViewDegrees
                : nil,
            stereoLayout: stereoLayout
        )
    }
}

struct PlaybackTopActionsState {
    var presentedMenu: PlaybackTopSecondaryMenu?
    var selectedDockEnvironment: SpatialSceneDomain.CinemaEnvironment
    var selectedEffect: SpatialSceneDomain.EnvironmentEffect?

    var projection: PlaybackModel.ProjectionType {
        get { videoFormatEditing.projection }
        set { videoFormatEditing.projection = newValue }
    }
    var horizontalFieldOfViewDegrees: Int {
        get { videoFormatEditing.horizontalFieldOfViewDegrees }
        set { videoFormatEditing.horizontalFieldOfViewDegrees = newValue }
    }
    var stereoLayout: PlaybackModel.StereoLayout {
        get { videoFormatEditing.stereoLayout }
        set { videoFormatEditing.stereoLayout = newValue }
    }

    private var videoFormatEditing: PlaybackVideoFormatEditingState

    init(
        presentedMenu: PlaybackTopSecondaryMenu? = nil,
        selectedDockEnvironment: SpatialSceneDomain.CinemaEnvironment = .quietRoom,
        selectedEffect: SpatialSceneDomain.EnvironmentEffect? = nil,
        projection: PlaybackModel.ProjectionType = .flat,
        horizontalFieldOfViewDegrees: Int = PanoramaHorizontalCoverage.defaultCustomAngle,
        stereoLayout: PlaybackModel.StereoLayout = .mono
    ) {
        self.presentedMenu = presentedMenu
        self.selectedDockEnvironment = selectedDockEnvironment
        self.selectedEffect = selectedEffect
        self.videoFormatEditing = PlaybackVideoFormatEditingState(
            projection: projection,
            horizontalFieldOfViewDegrees: horizontalFieldOfViewDegrees,
            stereoLayout: stereoLayout,
            beginsEditing: presentedMenu == .videoFormat
        )
    }

    mutating func toggleMenu(_ menu: PlaybackTopSecondaryMenu) {
        if presentedMenu == menu {
            dismissMenu()
            return
        }

        if presentedMenu == .videoFormat {
            videoFormatEditing.discard()
        }
        if menu == .videoFormat {
            videoFormatEditing.beginEditing()
        }
        presentedMenu = menu
    }

    mutating func dismissMenu() {
        if presentedMenu == .videoFormat {
            videoFormatEditing.discard()
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
            videoFormatEditing.discard()
            return nil
        case .apply:
            return videoFormatEditing.commit()
        }
    }

    mutating func synchronizeCommittedVideoFormat(
        _ selection: PlaybackVideoFormatSelection
    ) {
        videoFormatEditing.synchronizeCommittedVideoFormat(selection)
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

    mutating func synchronizeDockTarget(
        environment: SpatialSceneDomain.CinemaEnvironment,
        effect: SpatialSceneDomain.EnvironmentEffect?
    ) {
        selectedDockEnvironment = environment
        selectedEffect = effect
    }

}

struct PlaybackVideoFormatEditor: View {
    @Binding var projection: PlaybackModel.ProjectionType
    @Binding var horizontalFieldOfViewDegrees: Int
    @Binding var stereoLayout: PlaybackModel.StereoLayout

    let canApplyFormat: Bool
    let mediaFormatProvenance: MediaFormatProvenance
    let sourceMediaFormatSummary: String
    let contentWidth: CGFloat
    let identifierPrefix: String
    let onCancel: () -> Void
    let onApply: () -> Void
    let onRestoreAutomaticFormat: () -> Void
    let onReachabilityAction: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
            menuHeading("Video Format", supporting: "Choose how the video is presented")

            Button {
                onReachabilityAction("automatic")
                onRestoreAutomaticFormat()
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
            .accessibilityIdentifier("\(identifierPrefix)-automatic")

            Divider()

            formatPicker(
                title: String(localized: "Projection"),
                selection: presetProjectionSelection,
                options: [
                    PlaybackModel.ProjectionType.flat,
                    PlaybackModel.ProjectionType.equirectangular180,
                    .equirectangular360
                ],
                label: projectionTitle
            )

            customAngleRow

            formatPicker(
                title: String(localized: "Stereo Layout"),
                selection: stereoLayoutSelection,
                options: PlaybackModel.StereoLayout.userSelectableCases,
                label: stereoTitle
            )

            HStack {
                Spacer()
                Button("Cancel") {
                    onReachabilityAction("cancel")
                    onCancel()
                }
                    .accessibilityIdentifier("\(identifierPrefix)-cancel")
                Button("Apply") {
                    onReachabilityAction("apply")
                    onApply()
                }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("\(identifierPrefix)-apply")
            }
        }
#if DEBUG
        .onReceive(
            NotificationCenter.default.publisher(for: .debugMenuSelection)
        ) { notification in
            guard let request = notification.object as? DebugMenuSelectionRequest,
                  request.family == .customAngle else {
                return
            }
            let host: DebugMenuSelectionHost
            switch identifierPrefix {
            case "PlayerUI-VideoFormat": host = .playerUI
            case "PlayerPanel-VideoFormat": host = .playerPanel
            default: return
            }
            request.handle(
                host: host,
                family: .customAngle,
                items: PanoramaHorizontalCoverage.selectableAngles.map { degrees in
                    DebugMenuSelectionItem(
                        id: String(degrees),
                        title: String(localized: "\(degrees)°"),
                        isSelected: projection == .customAngle
                            && horizontalFieldOfViewDegrees == degrees,
                        select: { customAngleSelection.wrappedValue = Double(degrees) }
                    )
                }
            )
        }
#endif
    }

    private var customAngleRow: some View {
        let isCustom = projection == .customAngle
        return VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            HStack {
                Text("Custom Angle")
                    .font(DesignTokens.Typography.metadata)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Text("\(horizontalFieldOfViewDegrees)°")
                    .font(DesignTokens.Typography.metadata.monospacedDigit())
                    .foregroundStyle(
                        isCustom ? AnyShapeStyle(DesignTokens.Theme.accent) : AnyShapeStyle(.secondary)
                    )
            }

            DetentedRangeSlider(
                value: customAngleSelection,
                range: Double(PanoramaHorizontalCoverage.range.lowerBound)
                    ... Double(PanoramaHorizontalCoverage.range.upperBound),
                step: Double(PanoramaHorizontalCoverage.step),
                accessibilityLabel: String(localized: "Custom Angle"),
                accessibilityValue: String(localized: "\(horizontalFieldOfViewDegrees)°"),
                accessibilityIdentifier: "\(identifierPrefix)-CustomAngle",
                trackWidth: contentWidth
            )
            .opacity(isCustom ? 1 : DesignTokens.Interactive.inactiveSelectionOpacity)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Custom Angle")
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

    private var customAngleSelection: Binding<Double> {
        Binding(
            get: { Double(horizontalFieldOfViewDegrees) },
            set: { value in
                let degrees = PanoramaHorizontalCoverage.normalized(Int(value.rounded()))
                guard projection != .customAngle || degrees != horizontalFieldOfViewDegrees else {
                    return
                }
                onReachabilityAction("customAngle")
                projection = .customAngle
                horizontalFieldOfViewDegrees = degrees
            }
        )
    }

    private var presetProjectionSelection: Binding<PlaybackModel.ProjectionType?> {
        Binding(
            get: { projection == .customAngle ? nil : projection },
            set: { value in
                guard let value else { return }
                projection = value
            }
        )
    }

    private var stereoLayoutSelection: Binding<PlaybackModel.StereoLayout?> {
        Binding(
            get: { stereoLayout },
            set: { value in
                guard let value else { return }
                stereoLayout = value
            }
        )
    }

    private func formatPicker<Value: Hashable>(
        title: String,
        selection: Binding<Value?>,
        options: [Value],
        label: @escaping (Value) -> String
    ) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Text(title)
                .font(DesignTokens.Typography.metadata)
                .foregroundStyle(.secondary)
            HStack(spacing: .zero) {
                ForEach(options, id: \.self) { option in
                    let isSelected = selection.wrappedValue == option
                    Button {
                        onReachabilityAction("option.\(title).\(label(option))")
                        selection.wrappedValue = option
                    } label: {
                        Text(label(option))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background {
                                if isSelected {
                                    Capsule()
                                        .fill(DesignTokens.Surface.selected)
                                }
                            }
                            .contentShape(.interaction, Capsule())
                    }
                    .buttonStyle(EnchronPressFeedbackButtonStyle(.control))
                    .enchronHoverContentShape(Capsule())
                    .enchronHoverEffect(.automatic)
                    .contentShape(.interaction, Capsule())
                    .accessibilityIdentifier(
                        "\(identifierPrefix)-\(title)-\(label(option))"
                    )
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                    .accessibilityValue(isSelected ? "Selected" : "Not selected")
                }
            }
            .frame(height: DesignTokens.Interactive.regular)
            .clipShape(Capsule())
            .enchronButtonSurface(in: Capsule())
            .contentShape(Capsule())
            .accessibilityElement(children: .contain)
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

public struct PlaybackTopActions: View {
    private let controlsVisible: Bool
    private let immersiveEntryTarget: PlaybackPresentation?
    private let canApplyFormat: Bool
    private let mediaFormatProvenance: MediaFormatProvenance
    private let sourceMediaFormatSummary: String
    private let committedProjection: PlaybackModel.ProjectionType
    private let committedHorizontalFieldOfViewDegrees: Int
    private let committedStereoLayout: PlaybackModel.StereoLayout
    private let cardEnvironment: SpatialSceneDomain.CinemaEnvironment
    private let cardEnvironmentEffect: SpatialSceneDomain.EnvironmentEffect
    private let onEnterImmersive: ((SpatialSceneDomain.CinemaEnvironment?, SpatialSceneDomain.EnvironmentEffect?) -> Void)?
    private let onApplyFormat: ((PlaybackModel.ProjectionType, Int?, PlaybackModel.StereoLayout) -> Void)?
    private let onRestoreAutomaticFormat: (() -> Void)?
    private let onSecondaryMenuVisibilityChange: ((Bool) -> Void)?
    private let onReachabilityAction: (String) -> Void

    @State private var state: PlaybackTopActionsState

    public init(
        initialPresentedMenu: PlaybackTopSecondaryMenu? = nil,
        controlsVisible: Bool = true,
        immersiveEntryTarget: PlaybackPresentation? = .docked,
        canApplyFormat: Bool = true,
        mediaFormatProvenance: MediaFormatProvenance = .source,
        sourceMediaFormatSummary: String = "Flat · Mono",
        projection: PlaybackModel.ProjectionType = .flat,
        horizontalFieldOfViewDegrees: Int = PanoramaHorizontalCoverage.defaultCustomAngle,
        stereoLayout: PlaybackModel.StereoLayout = .mono,
        cardEnvironment: SpatialSceneDomain.CinemaEnvironment = .ocean,
        cardEnvironmentEffect: SpatialSceneDomain.EnvironmentEffect = .light,
        onEnterImmersive: ((SpatialSceneDomain.CinemaEnvironment?, SpatialSceneDomain.EnvironmentEffect?) -> Void)? = nil,
        onApplyFormat: ((PlaybackModel.ProjectionType, Int?, PlaybackModel.StereoLayout) -> Void)? = nil,
        onRestoreAutomaticFormat: (() -> Void)? = nil,
        onSecondaryMenuVisibilityChange: ((Bool) -> Void)? = nil,
        onReachabilityAction: @escaping (String) -> Void = { _ in }
    ) {
        self.controlsVisible = controlsVisible
        self.immersiveEntryTarget = immersiveEntryTarget
        self.canApplyFormat = canApplyFormat
        self.mediaFormatProvenance = mediaFormatProvenance
        self.sourceMediaFormatSummary = sourceMediaFormatSummary
        self.committedProjection = projection
        self.committedHorizontalFieldOfViewDegrees = horizontalFieldOfViewDegrees
        self.committedStereoLayout = stereoLayout
        self.cardEnvironment = cardEnvironment
        self.cardEnvironmentEffect = cardEnvironmentEffect
        self.onEnterImmersive = onEnterImmersive
        self.onApplyFormat = onApplyFormat
        self.onRestoreAutomaticFormat = onRestoreAutomaticFormat
        self.onSecondaryMenuVisibilityChange = onSecondaryMenuVisibilityChange
        self.onReachabilityAction = onReachabilityAction
        _state = State(
                initialValue: PlaybackTopActionsState(
                    presentedMenu: initialPresentedMenu,
                    selectedDockEnvironment: cardEnvironment,
                    selectedEffect: cardEnvironmentEffect,
                    projection: projection,
                    horizontalFieldOfViewDegrees: horizontalFieldOfViewDegrees,
                    stereoLayout: stereoLayout
                )
        )
    }

    public var body: some View {
        topButtonRow
            .onAppear {
                onSecondaryMenuVisibilityChange?(state.presentedMenu != nil)
            }
            .onDisappear {
                onSecondaryMenuVisibilityChange?(false)
            }
            .onChange(of: state.presentedMenu) { _, menu in
                onSecondaryMenuVisibilityChange?(menu != nil)
            }
            .onChange(of: controlsVisible) { _, visible in
                if visible == false { dismissMenu() }
            }
            .onChange(of: canApplyFormat) { _, available in
                if available == false, state.presentedMenu == .videoFormat { dismissMenu() }
            }
            .onChange(of: committedVideoFormatSelection) { _, selection in
                state.synchronizeCommittedVideoFormat(selection)
            }
            .onChange(of: cardEnvironment, initial: true) { _, environment in
                state.synchronizeDockTarget(
                    environment: environment,
                    effect: cardEnvironmentEffect
                )
            }
            .onChange(of: cardEnvironmentEffect) { _, effect in
                state.synchronizeDockTarget(
                    environment: cardEnvironment,
                    effect: effect
                )
            }
    }

    private var topButtonRow: some View {
        WindowPlaybackSpatialActions {
            if topActionsComposition.showsPanoramaEntry {
                PlaybackChromeGlassButton(
                    systemName: "rectangle.arrowtriangle.2.outward",
                    accessibilityLabel: String(localized: "Enter Panorama"),
                    action: {
                        onReachabilityAction("enterPanorama")
                        onEnterImmersive?(nil, nil)
                    },
                    accessibilityIdentifier: "PlayerUI-TopAction-resumePanorama"
                )
            } else if topActionsComposition.showsDock {
                PlaybackChromeGlassButton(
                    systemName: "mountain.2.fill",
                    accessibilityLabel: String(localized: "Dock"),
                    action: {
                        onReachabilityAction("dock.open")
                        toggle(.dock)
                    },
                    accessibilityIdentifier: "PlayerUI-TopAction-dock",
                    iconTier: .compact
                )
                .anchoredMenu(
                    isPresented: dockMenuIsPresented,
                    key: "playback.environment",
                    width: DesignTokens.Layout.environmentMenuWidth
                ) {
                    dockMenu
                }
            }
        } formatControl: {
            if topActionsComposition.showsVideoFormat {
                PlaybackChromeGlassButton(
                    systemName: "gear",
                    accessibilityLabel: String(localized: "Video Format"),
                    action: {
                        onReachabilityAction("videoFormat.open")
                        toggle(.videoFormat)
                    },
                    accessibilityIdentifier: "PlayerUI-TopAction-videoFormat"
                )
                .disabled(!canApplyFormat)
                .anchoredMenu(
                    isPresented: videoFormatMenuIsPresented,
                    key: "playback.videoFormat",
                    width: DesignTokens.Layout.videoFormatEditorWidth
                ) {
                    videoFormatMenu
                }
            }
        }
    }

    private var topActionsComposition: PlaybackTopActionsComposition {
        PlaybackTopActionsComposition(immersiveEntryTarget: immersiveEntryTarget)
    }

    private var dockMenu: some View {
        PlaybackDockMenuContent(
            cardEnvironment: dockCardEnvironment,
            selectedEnvironment: state.selectedDockEnvironment,
            selectedEffect: state.selectedEffect
        ) { environment, effect in
            onReachabilityAction(
                "dock.select"
                    + " environment=\(environment.rawValue)"
                    + " effect=\(effect?.rawValue ?? "none")"
            )
            let requested = state.selectDockTarget(
                environment: environment,
                effect: effect
            )
            onEnterImmersive?(requested.0, requested.1)
        }
    }

    private var dockMenuIsPresented: Binding<Bool> {
        Binding(
            get: { state.presentedMenu == .dock },
            set: { presented in
                guard presented == false, state.presentedMenu == .dock else { return }
                state.dismissMenu()
            }
        )
    }

    private var dockCardEnvironment: SpatialSceneDomain.CinemaEnvironment {
        cardEnvironment.isCardEnvironment ? cardEnvironment : .ocean
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
        PlaybackVideoFormatEditor(
            projection: $state.projection,
            horizontalFieldOfViewDegrees: $state.horizontalFieldOfViewDegrees,
            stereoLayout: $state.stereoLayout,
            canApplyFormat: canApplyFormat,
            mediaFormatProvenance: mediaFormatProvenance,
            sourceMediaFormatSummary: sourceMediaFormatSummary,
            contentWidth: DesignTokens.Layout.videoFormatEditorWidth
                - DesignTokens.Spacing.lg * 2 - DesignTokens.Menu.glassPadding * 2,
            identifierPrefix: "PlayerUI-VideoFormat",
            onCancel: cancelVideoFormat,
            onApply: applyVideoFormat,
            onRestoreAutomaticFormat: restoreAutomaticFormat,
            onReachabilityAction: { action in
                onReachabilityAction("videoFormat.\(action)")
            }
        )
        .padding(DesignTokens.Spacing.lg)
        .frame(width: DesignTokens.Menu.videoFormatContentWidth)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("PlayerUI-VideoFormat")
    }

    private var videoFormatMenuIsPresented: Binding<Bool> {
        Binding(
            get: { state.presentedMenu == .videoFormat },
            set: { presented in
                guard presented == false, state.presentedMenu == .videoFormat else { return }
                state.dismissMenu()
            }
        )
    }

}

/// The environment choices the player window's Dock entry offers. File playback
/// and streaming dock through this list, so both land in the same presentations
/// with the same choices.
struct PlaybackDockMenuContent: View {
    let cardEnvironment: SpatialSceneDomain.CinemaEnvironment
    let selectedEnvironment: SpatialSceneDomain.CinemaEnvironment?
    let selectedEffect: SpatialSceneDomain.EnvironmentEffect?
    let onSelect: (
        SpatialSceneDomain.CinemaEnvironment,
        SpatialSceneDomain.EnvironmentEffect?
    ) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Text("View in an environment")
                .font(DesignTokens.Typography.metadata)
                .foregroundStyle(.secondary)
                .padding(.horizontal, DesignTokens.Spacing.sm)

            item(
                environment: .quietRoom,
                effect: nil,
                thumbnailName: FeaturedEnvironment.quietRoomThumbnailName
            )

            Divider()
                .padding(.vertical, DesignTokens.Spacing.xs)

            item(
                environment: cardEnvironment,
                effect: .light,
                thumbnailName: thumbnailName(for: .light)
            )
            item(
                environment: cardEnvironment,
                effect: .dark,
                thumbnailName: thumbnailName(for: .dark)
            )
        }
        .padding(DesignTokens.Spacing.md)
        .frame(width: DesignTokens.Menu.environmentContentWidth)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("PlayerUI-DockMenu")
        .onAppear {
            EnvironmentSceneMapping.prefetch([.quietRoom, cardEnvironment], owner: .views)
        }
    }

    private func thumbnailName(
        for effect: SpatialSceneDomain.EnvironmentEffect
    ) -> String {
        FeaturedEnvironment.catalogEntry(for: cardEnvironment)?
            .imageName(for: effect)
            ?? FeaturedEnvironment.catalog[0].imageName(for: effect)
    }

    private func item(
        environment: SpatialSceneDomain.CinemaEnvironment,
        effect: SpatialSceneDomain.EnvironmentEffect?,
        thumbnailName: String
    ) -> some View {
        let shape = DesignTokens.ShapeToken.card
        let isSelected = selectedEnvironment == environment
            && (effect == nil || selectedEffect == effect)

        return Button {
            onSelect(environment, effect)
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
            .contentShape(.interaction, shape)
        }
        .buttonStyle(.plain)
        .background {
            if isSelected {
                shape.fill(DesignTokens.Surface.selected)
            }
        }
        .clipShape(shape)
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
                ?? "PlayerUI-DockMenu-default"
        )
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// The player window's Dock entry: the chip the window's chrome shows and the
/// environment menu it opens. It is the window's route into the immersive
/// presentations for file playback and streaming alike.
public struct PlaybackWindowDockAction: View {
    public init() {}

    public var body: some View {
        WindowPlaybackSpatialActions {
            PlaybackWindowDockChip()
        } formatControl: {
            EmptyView()
        }
    }
}

public struct PlaybackWindowDockChip: View {
    public init() {}

    public var body: some View {
        PlaybackDockMenuTrigger { isMenuPresented in
            PlaybackChromeGlassButton(
                systemName: "mountain.2.fill",
                accessibilityLabel: String(localized: "Dock"),
                action: { isMenuPresented.wrappedValue.toggle() },
                accessibilityIdentifier: "PlayerUI-TopAction-dock",
                iconTier: .compact
            )
        }
    }
}

struct PlaybackDockMenuTrigger<Label: View>: View {
    private let logger = Logger(subsystem: "app.enchron", category: "PlaybackDock")
    @Environment(PlaybackSessionModel.self) private var appModel
    @Environment(PlaybackRuntime.self) private var playbackRuntime
    @State private var isMenuPresented = false
    @State private var selectedEnvironment: SpatialSceneDomain.CinemaEnvironment?
    @State private var selectedEffect: SpatialSceneDomain.EnvironmentEffect?
    let label: (Binding<Bool>) -> Label

    var body: some View {
        label(menuIsPresented)
            .anchoredMenu(
                isPresented: menuIsPresented,
                key: "playback.environment",
                width: DesignTokens.Layout.environmentMenuWidth
            ) {
                PlaybackDockMenuContent(
                    cardEnvironment: cardEnvironment,
                    selectedEnvironment: selectedEnvironment ?? cardEnvironment,
                    selectedEffect: selectedEnvironment == nil
                        ? appModel.currentEnvironmentEffect
                        : selectedEffect
                ) { environment, effect in
                    selectedEnvironment = environment
                    selectedEffect = effect
                    isMenuPresented = false
                    enterDock(environment: environment, effect: effect)
                }
            }
    }

    private var menuIsPresented: Binding<Bool> {
        Binding(
            get: { isMenuPresented },
            set: { isMenuPresented = $0 }
        )
    }

    private var cardEnvironment: SpatialSceneDomain.CinemaEnvironment {
        let card = appModel.environmentContext.environment
            ?? appModel.centeredCardEnvironment
        return card.isCardEnvironment ? card : .ocean
    }

    private func enterDock(
        environment: SpatialSceneDomain.CinemaEnvironment,
        effect: SpatialSceneDomain.EnvironmentEffect?
    ) {
        appModel.registerControlsInteraction()
        guard playbackRuntime.canEnterSpatialPresentation,
              let target = appModel.playbackPresentation.enterImmersiveTarget else {
            return
        }
        do {
            _ = try appModel.requestPlaybackPresentation(
                target,
                environment: environment,
                effect: effect,
                mediaSessionID: playbackRuntime.activeSessionID,
                wasPlaying: playbackRuntime.productLifecycle == .playing
            )
        } catch {
            logger.error(
                "dock request failed error=\(error.localizedDescription, privacy: .public)"
            )
        }
    }
}

/// The Dock menu trigger for a control that lives in the player window's
/// ornament: the ornament is outside the window's coordinate space, so the
/// menu source is the window's bottom centre instead of the measured button.
public struct PlaybackDockMenuAnchor: View {
    private let logger = Logger(subsystem: "app.enchron", category: "PlaybackDock")
    @Environment(PlaybackSessionModel.self) private var appModel
    @Environment(PlaybackRuntime.self) private var playbackRuntime
    @Binding var isMenuPresented: Bool
    @State private var selectedEnvironment: SpatialSceneDomain.CinemaEnvironment?
    @State private var selectedEffect: SpatialSceneDomain.EnvironmentEffect?

    public init(isPresented: Binding<Bool>) {
        _isMenuPresented = isPresented
    }

    public var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .anchoredMenu(
                isPresented: $isMenuPresented,
                key: "playback.environment",
                width: DesignTokens.Layout.environmentMenuWidth,
                sourceAnchor: UnitPoint(x: 0.5, y: 1)
            ) {
                PlaybackDockMenuContent(
                    cardEnvironment: cardEnvironment,
                    selectedEnvironment: selectedEnvironment ?? cardEnvironment,
                    selectedEffect: selectedEnvironment == nil
                        ? appModel.currentEnvironmentEffect
                        : selectedEffect
                ) { environment, effect in
                    selectedEnvironment = environment
                    selectedEffect = effect
                    isMenuPresented = false
                    enterDock(environment: environment, effect: effect)
                }
            }
    }

    private var cardEnvironment: SpatialSceneDomain.CinemaEnvironment {
        let card = appModel.environmentContext.environment
            ?? appModel.centeredCardEnvironment
        return card.isCardEnvironment ? card : .ocean
    }

    private func enterDock(
        environment: SpatialSceneDomain.CinemaEnvironment,
        effect: SpatialSceneDomain.EnvironmentEffect?
    ) {
        appModel.registerControlsInteraction()
        guard playbackRuntime.canEnterSpatialPresentation,
              let target = appModel.playbackPresentation.enterImmersiveTarget else {
            return
        }
        do {
            _ = try appModel.requestPlaybackPresentation(
                target,
                environment: environment,
                effect: effect,
                mediaSessionID: playbackRuntime.activeSessionID,
                wasPlaying: playbackRuntime.productLifecycle == .playing
            )
        } catch {
            logger.error(
                "dock request failed error=\(error.localizedDescription, privacy: .public)"
            )
        }
    }
}
