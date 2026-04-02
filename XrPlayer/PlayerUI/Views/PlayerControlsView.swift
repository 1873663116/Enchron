import SwiftUI

public struct PlayerControlsView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(WindowVideoViewModel.self) private var videoViewModel
    @Environment(FileBrowsingViewModel.self) private var fileBrowsingViewModel
    @Environment(PlaybackLaunchCoordinator.self) private var launcher
    @Environment(PanoramaLayerBridge.self) private var panoramaBridge
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace

    @State private var isDraggingSlider = false
    @State private var dragValue: Double = 0
    @State private var showPlaybackSettingsPanel = false
    @State private var showScreenPositionPanel = false
    @State private var showDebugPanel = false
    @State private var hasAppliedSmokePanelRequest = false

    public init() {}

    public var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 24) {  // Increased vertical rhythm
                sliderSection

                VStack(spacing: 28) {  // More space between controls for clarity
                    primaryControlRow
                    secondaryControlRow
                }
                .padding(.bottom, 8)
            }

            if showPlaybackSettingsPanel {
                PlaybackMenuView {
                    closePlaybackSettingsPanel()
                }
                .frame(width: 340, height: 420, alignment: .topLeading)
                .padding(.top, 12)
                .padding(.trailing, 12)
                .transition(
                    .opacity
                        .combined(with: .scale(scale: 0.96, anchor: .topTrailing))
                        .combined(with: .offset(y: -8))
                )
                .zIndex(2)
            }

            if showScreenPositionPanel {
                ScreenPositionControlView {
                    closeScreenPositionPanel()
                }
                .frame(width: 340, height: 420, alignment: .topLeading)
                .padding(.top, 12)
                .padding(.trailing, 12)
                .transition(
                    .opacity
                        .combined(with: .scale(scale: 0.96, anchor: .topTrailing))
                        .combined(with: .offset(y: -8))
                )
                .zIndex(3)
            }

            if showDebugPanel {
                DebugOverlayView {
                    closeDebugPanel()
                }
                .frame(width: 340, height: 480, alignment: .topLeading)
                .padding(.top, 12)
                .padding(.trailing, 12)
                .transition(
                    .opacity
                        .combined(with: .scale(scale: 0.96, anchor: .topTrailing))
                        .combined(with: .offset(y: -8))
                )
                .zIndex(4)
            }
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 28)
        .frame(width: 720)
        .glassBackgroundEffect()  // Base spatial material
        .background(
            .ultraThinMaterial, in: RoundedRectangle(cornerRadius: 32, style: .continuous)
        )  // Nested glass layering
        .onHover { isHovering in
            appModel.setControlsFocused(
                isHovering || showPlaybackSettingsPanel || showScreenPositionPanel || showDebugPanel)
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    appModel.registerControlsInteraction()
                    if appModel.showControls == false {
                        appModel.showControls = true
                    }
                }
        )
        .onChange(of: showPlaybackSettingsPanel) { _, isVisible in
            appModel.setControlsFocused(isVisible || showScreenPositionPanel || showDebugPanel)
            appModel.registerControlsInteraction()
        }
        .onChange(of: showScreenPositionPanel) { _, isVisible in
            appModel.setControlsFocused(isVisible || showPlaybackSettingsPanel || showDebugPanel)
            appModel.registerControlsInteraction()
        }
        .onChange(of: showDebugPanel) { _, isVisible in
            appModel.setControlsFocused(isVisible || showPlaybackSettingsPanel || showScreenPositionPanel)
            appModel.registerControlsInteraction()
        }
        .onChange(of: appModel.currentPlaybackURL) { _, _ in
            resetTransientPanelsForMediaSwitch()
            appModel.registerControlsInteraction()
        }
        .task(id: appModel.smokePanelRequest) {
            await applySmokePanelRequestIfNeeded()
        }
    }

    @ViewBuilder
    private var sliderSection: some View {
        VStack(spacing: 6) {
            HStack(spacing: 12) {
                Text(
                    PlaybackTimeFormatter.clock(
                        isDraggingSlider ? dragValue : videoViewModel.playbackPosition.seconds)
                )
                .font(.caption2.monospacedDigit())
                .frame(width: 60, alignment: .leading)

                Slider(
                    value: Binding(
                        get: {
                            isDraggingSlider ? dragValue : videoViewModel.playbackPosition.seconds
                        },
                        set: { dragValue = $0 }
                    ),
                    in: 0...max(videoViewModel.playbackPosition.duration, 1),
                    onEditingChanged: { editing in
                        isDraggingSlider = editing
                        if !editing {
                            videoViewModel.seek(to: dragValue)
                        }
                    }
                )
                .tint(.white)
                .frame(minHeight: 44)

                Text(PlaybackTimeFormatter.clock(videoViewModel.playbackPosition.duration))
                    .font(.caption2.monospacedDigit())
                    .frame(width: 60, alignment: .trailing)
            }
            .padding(.vertical, 8)

            // Precision time label — visible during drag
            if isDraggingSlider {
                Text(
                    PlaybackTimeFormatter.preciseClock(
                        dragValue,
                        framesPerSecond: videoViewModel.displayMediaProfile?.frameRate ?? 0
                    )
                )
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.orange)
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: isDraggingSlider)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var primaryControlRow: some View {
        HStack(spacing: 40) {
            Button {
                videoViewModel.skip(by: -10)
            } label: {
                Image(systemName: "gobackward.10")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.primary)
            }
            .buttonStyle(PlayerControlSurfaceStyle(size: 72, prominence: .primary))
            .help("Backward 10s")

            Button {
                if videoViewModel.playbackState == .ended {
                    videoViewModel.replay()
                } else if videoViewModel.playbackState == .playing {
                    videoViewModel.pause()
                } else {
                    videoViewModel.resume()
                }
            } label: {
                Image(systemName: playButtonIcon)
                    .font(.system(size: 44, weight: .medium))
                    .foregroundStyle(.primary)
            }
            .buttonStyle(
                PlayerControlSurfaceStyle(
                    size: 72,
                    isSelected: videoViewModel.playbackState == .playing,
                    prominence: .primary
                )
            )

            Button {
                videoViewModel.skip(by: 10)
            } label: {
                Image(systemName: "goforward.10")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.primary)
            }
            .buttonStyle(PlayerControlSurfaceStyle(size: 72, prominence: .primary))
            .help("Forward 10s")
        }
    }

    private var playButtonIcon: String {
        switch videoViewModel.playbackState {
        case .playing:
            return "pause.fill"
        case .ended:
            return "arrow.counterclockwise"
        default:
            return "play.fill"
        }
    }

    @ViewBuilder
    private var secondaryControlRow: some View {
        HStack(spacing: 24) {
            speedMenu
            playbackSettingsButton
            playbackModeMenu
            projectionMenu
            if appModel.immersiveSpaceState == .open {
                screenPositionButton
            }
            playlistMenu
            infoMenu
            debugButton

            Button {
                videoViewModel.frameStepBackward()
            } label: {
                Image(systemName: "backward.frame.fill")
                    .font(.title3)
                    .foregroundStyle(.primary)
            }
            .buttonStyle(PlayerControlSurfaceStyle(size: 60))
            .help("Frame Step Backward")

            Button {
                videoViewModel.frameStepForward()
            } label: {
                Image(systemName: "forward.frame.fill")
                    .font(.title3)
                    .foregroundStyle(.primary)
            }
            .buttonStyle(PlayerControlSurfaceStyle(size: 60))
            .help("Frame Step Forward")
        }
    }

    private var playbackSettingsButton: some View {
        Button {
            appModel.registerControlsInteraction()
            withAnimation(.spring(response: 0.26, dampingFraction: 0.9)) {
                closeScreenPositionPanel()
                closeDebugPanel()
                showPlaybackSettingsPanel.toggle()
            }
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.title3)
                .foregroundStyle(showPlaybackSettingsPanel ? Color.accentColor : Color.primary)
        }
        .buttonStyle(PlayerControlSurfaceStyle(size: 60, isSelected: showPlaybackSettingsPanel))
        .help("Playback Settings")
    }

    private var screenPositionButton: some View {
        Button {
            appModel.registerControlsInteraction()
            withAnimation(.spring(response: 0.26, dampingFraction: 0.9)) {
                closePlaybackSettingsPanel()
                closeDebugPanel()
                showScreenPositionPanel.toggle()
            }
        } label: {
            Image(systemName: "move.3d")
                .font(.title3)
                .foregroundStyle(showScreenPositionPanel ? Color.accentColor : Color.primary)
        }
        .buttonStyle(PlayerControlSurfaceStyle(size: 60, isSelected: showScreenPositionPanel))
        .help("Screen Position")
    }

    private var infoMenu: some View {
        Menu {
            Section("Media Info") {
                if let profile = videoViewModel.displayMediaProfile {
                    Text(PlaybackInfoFormatter.hdrTypeLabel(profile.hdrType))
                    Text("Resolution: \(profile.resolution.width)×\(profile.resolution.height)")
                    Text("Frame Rate: \(PlaybackInfoFormatter.frameRate(profile.frameRate))")
                } else {
                    Text("Loading media profile…")
                }

                Text("File Size: \(PlaybackInfoFormatter.fileSize(videoViewModel.displayFileSizeInBytes))")
            }
        } label: {
            Image(systemName: "info.circle")
                .font(.title3)
                .foregroundStyle(.primary)
                .playerControlSurface(size: 60)
        }
        .buttonStyle(.plain)
        .help("Media Info")
    }

    private var speedMenu: some View {
        Menu {
            ForEach(PlaybackCoreDomain.PlaybackSpeed.allCases, id: \.self) { speed in
                Button {
                    videoViewModel.setSpeed(speed)
                    appModel.updatePlaybackSpeed(speed)
                } label: {
                    if appModel.playbackSpeed == speed {
                        Label(speedLabel(speed), systemImage: "checkmark")
                    } else {
                        Text(speedLabel(speed))
                    }
                }
            }
        } label: {
            Text(String(format: "%.1f\u{00D7}", appModel.playbackSpeed.value))
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.primary)
                .playerControlSurface(size: 60)
        }
        .buttonStyle(.plain)
    }

    private var playlistMenu: some View {
        Menu {
            if fileBrowsingViewModel.files.isEmpty {
                Text("No playlist items")
            } else {
                ForEach(fileBrowsingViewModel.files, id: \.id) { file in
                    Button {
                        Task {
                            do {
                                let request = try await fileBrowsingViewModel.playbackRequest(
                                    for: file)
                                await MainActor.run {
                                    launcher.beginPlayback(request)
                                }
                            } catch {
                                await MainActor.run {
                                    fileBrowsingViewModel.lastErrorMessage =
                                        "Failed to open \"\(file.name)\": \(error.localizedDescription)"
                                }
                            }
                        }
                    } label: {
                        if appModel.currentPlaybackURL?.lastPathComponent == file.name {
                            Label(file.name, systemImage: "checkmark")
                        } else {
                            Text(file.name)
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "list.bullet")
                .font(.title3)
                .foregroundStyle(.primary)
                .playerControlSurface(size: 60)
        }
        .buttonStyle(.plain)
        .help("Playlist")
    }

    private var playbackModeMenu: some View {
        Menu {
            ForEach(PlaybackMode.allCases, id: \.self) { mode in
                Button {
                    Task {
                        await switchPlaybackMode(to: mode)
                    }
                } label: {
                    if appModel.playbackMode == mode {
                        Label(playbackModeLabel(mode), systemImage: "checkmark")
                    } else {
                        Label(playbackModeLabel(mode), systemImage: playbackModeIcon(mode))
                    }
                }
                .disabled(mode == appModel.playbackMode || appModel.immersiveSpaceState == .inTransition)
            }
        } label: {
            Image(systemName: playbackModeIcon(appModel.playbackMode))
                .font(.title3)
                .foregroundStyle(.primary)
                .playerControlSurface(size: 60)
        }
        .buttonStyle(.plain)
        .help("Playback Mode: \(appModel.playbackMode.rawValue)")
    }

    private func switchPlaybackMode(to mode: PlaybackMode) async {
        let currentMode = appModel.playbackMode
        guard mode != currentMode else { return }

        // Step 1: stop bridge if leaving panorama or immersive
        if currentMode == .panorama || currentMode == .immersive {
            panoramaBridge.attachVideoLayer(nil)
        }

        // Step 2: close immersive space if we're leaving immersive/panorama
        if currentMode == .immersive || currentMode == .panorama {
            if appModel.immersiveSpaceState == .open {
                appModel.immersiveSpaceState = .inTransition
                await dismissImmersiveSpace()
            }
        }

        // Step 3: open immersive space if entering immersive/panorama
        if mode == .immersive || mode == .panorama {
            appModel.immersiveSpaceState = .inTransition
            switch await openImmersiveSpace(id: appModel.immersiveSpaceID) {
            case .opened:
                break
            case .userCancelled, .error:
                appModel.immersiveSpaceState = .closed
                appModel.updatePlaybackMode(.window)
                return
            @unknown default:
                appModel.immersiveSpaceState = .closed
                appModel.updatePlaybackMode(.window)
                return
            }
        }

        // Step 4: update the mode
        appModel.updatePlaybackMode(mode)

        // Step 5: start bridge if entering panorama or immersive
        if mode == .panorama || mode == .immersive {
            let layer = videoViewModel.nativeVideoLayer
            panoramaBridge.attachVideoLayer(layer)
        }
    }

    private func playbackModeLabel(_ mode: PlaybackMode) -> String {
        switch mode {
        case .window: return "Window"
        case .immersive: return "Immersive"
        case .panorama: return "Panorama"
        }
    }

    private func playbackModeIcon(_ mode: PlaybackMode) -> String {
        switch mode {
        case .window: return "rectangle.inset.filled"
        case .immersive: return "visionpro"
        case .panorama: return "pano"
        }
    }

    private var projectionMenu: some View {
        Menu {
            Button {
                appModel.setProjectionOverride(nil)
            } label: {
                if appModel.projectionOverride == nil {
                    Label("Auto (\(projectionLabel(appModel.detectedProjectionType)))", systemImage: "checkmark")
                } else {
                    Text("Auto (\(projectionLabel(appModel.detectedProjectionType)))")
                }
            }

            Divider()

            ForEach(PlaybackCoreDomain.ProjectionType.allCases, id: \.self) { type in
                Button {
                    appModel.setProjectionOverride(type)
                } label: {
                    if appModel.projectionOverride == type {
                        Label(projectionLabel(type), systemImage: "checkmark")
                    } else {
                        Text(projectionLabel(type))
                    }
                }
            }
        } label: {
            Image(systemName: projectionIcon(appModel.effectiveProjectionType))
                .font(.title3)
                .foregroundStyle(.primary)
                .playerControlSurface(size: 60)
        }
        .buttonStyle(.plain)
        .help("Projection: \(projectionLabel(appModel.effectiveProjectionType))")
    }

    private func projectionLabel(_ type: PlaybackCoreDomain.ProjectionType) -> String {
        switch type {
        case .flat: return "Flat"
        case .stereoscopicSBS: return "3D SBS"
        case .stereoscopicOU: return "3D OU"
        case .panorama360: return "360\u{00B0}"
        case .panorama180: return "180\u{00B0}"
        case .fisheye: return "Fisheye"
        }
    }

    private func projectionIcon(_ type: PlaybackCoreDomain.ProjectionType) -> String {
        switch type {
        case .flat: return "rectangle"
        case .stereoscopicSBS: return "rectangle.split.2x1"
        case .stereoscopicOU: return "rectangle.split.1x2"
        case .panorama360: return "pano"
        case .panorama180: return "circle.lefthalf.filled"
        case .fisheye: return "camera.filters"
        }
    }

    private var debugButton: some View {
        Button {
            appModel.registerControlsInteraction()
            withAnimation(.spring(response: 0.26, dampingFraction: 0.9)) {
                closePlaybackSettingsPanel()
                closeScreenPositionPanel()
                showDebugPanel.toggle()
            }
        } label: {
            Image(systemName: "ladybug")
                .font(.title3)
                .foregroundStyle(showDebugPanel ? Color.accentColor : Color.primary)
        }
        .buttonStyle(PlayerControlSurfaceStyle(size: 60, isSelected: showDebugPanel))
        .help("Debug Controls")
    }

    @MainActor
    private func applySmokePanelRequestIfNeeded() async {
        guard hasAppliedSmokePanelRequest == false,
            appModel.smokePanelRequest != nil
        else {
            return
        }

        hasAppliedSmokePanelRequest = true
        appModel.showControls = true
    }

    private func speedLabel(_ speed: PlaybackCoreDomain.PlaybackSpeed) -> String {
        String(format: "%.2f\u{00D7}", speed.value)
    }

    private func closePlaybackSettingsPanel() {
        showPlaybackSettingsPanel = false
    }

    private func closeScreenPositionPanel() {
        showScreenPositionPanel = false
    }

    private func closeDebugPanel() {
        showDebugPanel = false
    }

    private func resetTransientPanelsForMediaSwitch() {
        showPlaybackSettingsPanel = false
        showScreenPositionPanel = false
        showDebugPanel = false
    }
}

#Preview {
    let appModel = AppModel()
    let windowVideoViewModel = WindowVideoViewModel(player: MPVPlayerAdapter())
    let launcher = PlaybackLaunchCoordinator(
        appModel: appModel,
        windowVideoViewModel: windowVideoViewModel
    )
    let fileBrowsingViewModel = FileBrowsingViewModel(localDataSource: LocalDataSourceAdapter()) {
        request in
        launcher.beginPlayback(request)
    }

    PlayerControlsView()
        .environment(appModel)
        .environment(windowVideoViewModel)
        .environment(fileBrowsingViewModel)
        .environment(launcher)
        .environment(PanoramaLayerBridge())
}
