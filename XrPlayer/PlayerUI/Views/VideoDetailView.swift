import SwiftUI

/// Shows media metadata, environment selection, and track selection before the user confirms playback.
///
/// Presented as a `.sheet(item:)` from FileBrowserView.
/// Observes `PlaybackLaunchCoordinator.currentPreparation` to progressively
/// reveal metadata as it resolves. The user can select audio/subtitle tracks,
/// choose a cinema environment, and tap Play to confirm. Sheet dismiss cancels preparation.
public struct VideoDetailView: View {
    @Environment(PlaybackLaunchCoordinator.self) private var coordinator
    @Environment(AppModel.self) private var appModel
    @Environment(ThumbnailService.self) private var thumbnailService
    @Environment(\.dismiss) private var dismiss

    @AccessibilityFocusState private var isTitleFocused: Bool
    @State private var savedProgress: PersistenceDomain.PlaybackProgress?
    @State private var resumePolicy: PersistenceDomain.ResumePolicy = .askEveryTime
    @State private var selectedAudioTrackID: String?
    @State private var selectedSubtitleTrackID: String?
    @State private var subtitlesOff: Bool = false
    @State private var hdrOutputEnabled: Bool = true
    @State private var thumbnail: CGImage?
    @State private var selectedPlaybackMode: PlaybackMode = .window

    public init() {}

    public var body: some View {
        NavigationStack {
            Group {
                switch coordinator.currentPreparation {
                case .preparing(let request, let metadata):
                    preparingContent(request: request, metadata: metadata)

                case .ready(let prepared):
                    readyContent(prepared: prepared)

                case .failed(let error):
                    failedContent(error: error)

                case nil:
                    ContentUnavailableView("No Video Selected", systemImage: "film")
                }
            }
            .navigationTitle(currentDisplayName)
            .navigationBarTitleDisplayMode(.inline)
            .accessibilityFocused($isTitleFocused)
            .onAppear { isTitleFocused = true }
            .task(id: currentRequestURL) {
                guard let file = currentMediaFileForThumbnail else { return }
                thumbnail = await thumbnailService.thumbnail(for: file)
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .accessibilityIdentifier("videoDetail.backButton")
                    .accessibilityLabel("Back")
                }
            }
        }
        .onDisappear {
            if coordinator.currentPreparation != nil {
                coordinator.cancelPreparedPlayback()
            }
        }
    }

    private var currentDisplayName: String {
        switch coordinator.currentPreparation {
        case .preparing(let request, _):
            return request.displayName
        case .ready(let prepared):
            return prepared.request.displayName
        case .failed, nil:
            return "Video Details"
        }
    }

    /// Stable identity for the `.task(id:)` thumbnail loader.
    private var currentRequestURL: URL? {
        switch coordinator.currentPreparation {
        case .preparing(let request, _): return request.url
        case .ready(let prepared): return prepared.request.url
        case .failed, nil: return nil
        }
    }

    /// Minimal MediaFile constructed from the current request for thumbnail lookup.
    private var currentMediaFileForThumbnail: FileBrowsingDomain.MediaFile? {
        guard let url = currentRequestURL else { return nil }
        let name = url.lastPathComponent
        let ext = url.pathExtension.lowercased()
        return FileBrowsingDomain.MediaFile(
            name: name,
            sizeInBytes: 0,
            modifiedAt: Date(timeIntervalSince1970: 0),
            fileExtension: ext,
            url: url
        )
    }

    // MARK: - Preparing State

    @ViewBuilder
    private func preparingContent(
        request: PlaybackLaunchRequest,
        metadata: PlaybackMediaMetadata?
    ) -> some View {
        GeometryReader { proxy in
            let totalWidth = proxy.size.width - 56 // account for padding (28 each side)
            let leftWidth = max(totalWidth * 0.6, 300)
            HStack(alignment: .top, spacing: 0) {
                // Left column: preview with play overlay + environment selector
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        videoPreviewPlaceholder()
                        environmentSelector()
                    }
                }
                .frame(width: leftWidth)
                .padding(.trailing, 14)

                // Right column: title & meta + metadata + loading indicator
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        titleSection(displayName: request.displayName, metadata: metadata)
                        if let metadata {
                            metadataSection(metadata: metadata)
                        }
                        ProgressView("Loading media information...")
                            .padding(.top, 8)
                        Spacer(minLength: 0)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 14)
            }
            .padding(28)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    // MARK: - Ready State

    @ViewBuilder
    private func readyContent(prepared: PreparedPlayback) -> some View {
        GeometryReader { proxy in
            let totalWidth = proxy.size.width - 56
            let leftWidth = max(totalWidth * 0.6, 300)
            HStack(alignment: .top, spacing: 0) {
                // Left column: preview with play overlay + environment selector
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        videoPreviewWithPlay(displayName: prepared.request.displayName, prepared: prepared)
                        environmentSelector()
                    }
                }
                .frame(width: leftWidth)
                .padding(.trailing, 14)

                // Right column: title & meta + metadata + tracks
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        titleSection(displayName: prepared.request.displayName, metadata: prepared.metadata)

                        if let metadata = prepared.metadata {
                            metadataSection(metadata: metadata)
                        }

                        playbackSettingsSection(prepared: prepared)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 14)
            }
            .padding(28)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .task {
            guard let fileID = prepared.request.fileIdentifier else { return }
            savedProgress = await coordinator.loadProgress(for: fileID)
            resumePolicy = coordinator.currentResumePolicy()
        }
    }

    private static func formatTime(_ totalSeconds: Double) -> String {
        let seconds = Int(totalSeconds)
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }

    // MARK: - Failed State

    @ViewBuilder
    private func failedContent(error: Error) -> some View {
        ContentUnavailableView {
            Label("Failed to Load", systemImage: "exclamationmark.triangle")
        } description: {
            Text(error.localizedDescription)
        } actions: {
            Button("Retry") {
                coordinator.cancelPreparedPlayback()
            }
            Button("Close") {
                coordinator.cancelPreparedPlayback()
                dismiss()
            }
        }
    }

    // MARK: - Title Section (glass-sub panel, right column)

    @ViewBuilder
    private func titleSection(displayName: String, metadata: PlaybackMediaMetadata?) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Tag badges
            HStack(spacing: 8) {
                tagBadge("Local File", color: Color.enchronTertiary)
                if let profile = metadata?.mediaProfile {
                    tagBadge(
                        PlaybackInfoFormatter.videoCodecLabel(profile.videoCodec),
                        color: Color.enchronOnSurfaceVariant.opacity(0.7)
                    )
                }
            }

            Text(displayName)
                .font(.title2.weight(.heavy))
                .tracking(-0.3)
                .lineLimit(2)

            if let metadata, let profile = metadata.mediaProfile {
                Text("Duration: \(PlaybackInfoFormatter.duration(profile.durationSeconds))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: DesignTokens.Radius.card, style: .continuous))
    }

    @ViewBuilder
    private func tagBadge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2)
            .fontWeight(.bold)
            .textCase(.uppercase)
            .tracking(1.5)
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: DesignTokens.Radius.badge, style: .continuous))
    }

    // MARK: - Video Preview

    @ViewBuilder
    private func videoPreviewPlaceholder() -> some View {
        RoundedRectangle(cornerRadius: DesignTokens.Radius.card, style: .continuous)
            .fill(.quaternary)
            .aspectRatio(16/9, contentMode: .fit)
            .overlay {
                if let cgImage = thumbnail {
                    Image(cgImage, scale: 1.0, label: Text(""))
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .clipped()
                } else {
                    Image(systemName: "film")
                        .font(DesignTokens.SymbolSize.hero)
                        .foregroundStyle(.secondary)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.card, style: .continuous))
    }

    // MARK: - Video Preview with Play Overlay

    @ViewBuilder
    private func videoPreviewWithPlay(displayName: String, prepared: PreparedPlayback) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.card, style: .continuous)
                .fill(.quaternary)
                .aspectRatio(16/9, contentMode: .fit)
                .overlay {
                    if let cgImage = thumbnail {
                        Image(cgImage, scale: 1.0, label: Text(""))
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .clipped()
                    } else {
                        Image(systemName: "film")
                            .font(DesignTokens.SymbolSize.hero)
                            .foregroundStyle(.secondary)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.card, style: .continuous))

            // Play button overlay centered on preview
            playbackOverlay(prepared: prepared)
        }
    }

    @ViewBuilder
    private func playbackOverlay(prepared: PreparedPlayback) -> some View {
        if let progress = savedProgress, progress.position.seconds > 5 {
            switch resumePolicy {
            case .askEveryTime:
                VStack(spacing: 10) {
                    overlayPlayButton(
                        label: "Resume from \(Self.formatTime(progress.position.seconds))",
                        icon: "play.fill"
                    ) {
                        confirmWithSelections(prepared, resumePosition: progress.position.seconds)
                    }
                    Button {
                        confirmWithSelections(prepared)
                    } label: {
                        Text("Play from Start")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                }
            case .alwaysResume:
                overlayPlayButton(label: "Resume", icon: "play.fill") {
                    confirmWithSelections(prepared, resumePosition: progress.position.seconds)
                }
            case .alwaysStartFromBeginning:
                overlayPlayButton(label: "Play", icon: "play.fill") {
                    confirmWithSelections(prepared)
                }
            }
        } else {
            overlayPlayButton(label: "Start Playback", icon: "play.fill") {
                confirmWithSelections(prepared)
            }
        }
    }

    @ViewBuilder
    private func overlayPlayButton(label: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.body.weight(.semibold))
                Text(label)
                    .font(.body.weight(.semibold))
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 14)
            .background(Color.enchronPrimary.opacity(0.9))
            .foregroundStyle(Color.enchronOnPrimary)
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.card, style: .continuous))
            .shadow(color: .white.opacity(0.15), radius: 20)
        }
        .buttonStyle(.plain)
        .hoverEffect(.lift)
    }

    // MARK: - Environment Selector

    @ViewBuilder
    private func environmentSelector() -> some View {
        VStack(spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(SpatialSceneDomain.CinemaEnvironment.allCases, id: \.self) { env in
                        let isSelected = appModel.currentCinemaEnvironment == env
                        Button {
                            Task {
                                await appModel.switchEnvironment(to: env)
                            }
                        } label: {
                            VStack(spacing: 6) {
                                RoundedRectangle(cornerRadius: DesignTokens.Radius.badge, style: .continuous)
                                    .fill(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
                                    .frame(width: isSelected ? 100 : 72, height: isSelected ? 64 : 48)
                                    .overlay {
                                        Image(systemName: environmentIcon(env))
                                            .font(isSelected ? .title2 : .title3)
                                            .foregroundStyle(isSelected ? .primary : .secondary)
                                    }
                                    .overlay(
                                        RoundedRectangle(cornerRadius: DesignTokens.Radius.badge, style: .continuous)
                                            .strokeBorder(isSelected ? Color.enchronPrimary.opacity(0.4) : .clear, lineWidth: 0.5)
                                    )
                                    .opacity(isSelected ? 1 : 0.6)
                                    .animation(.easeInOut(duration: 0.3), value: isSelected)
                            }
                        }
                        .buttonStyle(.plain)
                        .hoverEffect(.lift)
                        .contentShape(.rect)
                        .accessibilityLabel(env.displayName)
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)

            VStack(spacing: 2) {
                Text(appModel.currentCinemaEnvironment.displayName)
                    .font(.subheadline.weight(.bold))
                    .tracking(1)
                    .textCase(.uppercase)
                Text("Immersive Environment")
                    .font(DesignTokens.Typography.sectionHeader)
                    .textCase(.uppercase)
                    .tracking(2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: DesignTokens.Radius.card, style: .continuous))
    }

    private func environmentIcon(_ env: SpatialSceneDomain.CinemaEnvironment) -> String {
        switch env {
        case .darkTheatre: return "theatermasks"
        case .starryNight: return "moon.stars"
        case .sunsetNature: return "sun.horizon"
        }
    }

    // MARK: - Metadata Section

    @ViewBuilder
    private func metadataSection(metadata: PlaybackMediaMetadata) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Video Metadata")
                .font(DesignTokens.Typography.sectionHeader)
                .fontWeight(.bold)
                .textCase(.uppercase)
                .tracking(1.5)
                .foregroundStyle(.secondary)

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), alignment: .leading),
                    GridItem(.flexible(), alignment: .leading)
                ],
                spacing: 16
            ) {
                if let profile = metadata.mediaProfile {
                    metadataRow(
                        label: "Resolution",
                        value: "\(profile.resolution.width) \u{00D7} \(profile.resolution.height)"
                    )

                    metadataRow(
                        label: "Dynamic Range",
                        value: PlaybackInfoFormatter.hdrTypeLabel(profile.hdrType)
                    )

                    metadataRow(
                        label: "Video Codec",
                        value: PlaybackInfoFormatter.videoCodecLabel(profile.videoCodec)
                    )

                    metadataRow(
                        label: "Frame Rate",
                        value: PlaybackInfoFormatter.frameRate(profile.frameRate)
                    )

                    metadataRow(
                        label: "Duration",
                        value: PlaybackInfoFormatter.duration(profile.durationSeconds)
                    )

                    metadataRow(
                        label: "Projection",
                        value: projectionLabel(profile.projectionType)
                    )
                }

                metadataRow(
                    label: "File Size",
                    value: PlaybackInfoFormatter.fileSize(metadata.fileSizeInBytes)
                )
            }
        }
        .padding(20)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: DesignTokens.Radius.card, style: .continuous))
    }

    @ViewBuilder
    private func metadataRow(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(DesignTokens.Typography.sectionHeader)
                .textCase(.uppercase)
                .tracking(1.5)
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.body.weight(.bold))
        }
    }

    // MARK: - Playback Settings Section (interactive)

    @ViewBuilder
    private func playbackSettingsSection(prepared: PreparedPlayback) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Playback Settings")
                .font(DesignTokens.Typography.sectionHeader)
                .fontWeight(.bold)
                .textCase(.uppercase)
                .tracking(1.5)
                .foregroundStyle(.secondary)

            if !prepared.subtitleTracks.isEmpty {
                subtitlePicker(tracks: prepared.subtitleTracks)
            }
            if !prepared.audioTracks.isEmpty {
                audioTrackPicker(tracks: prepared.audioTracks)
            }
            if let profile = prepared.metadata?.mediaProfile,
               profile.hdrType != .sdr {
                hdrOutputToggle(hdrType: profile.hdrType)
            }
            playbackModePickerSection(prepared: prepared)
        }
        .padding(20)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: DesignTokens.Radius.card, style: .continuous))
        .onAppear {
            initializeTrackSelections(prepared: prepared)
        }
    }

    @ViewBuilder
    private func subtitlePicker(tracks: [PlaybackCoreDomain.SubtitleTrack]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Subtitles")
                .font(DesignTokens.Typography.sectionHeader)
                .textCase(.uppercase)
                .tracking(1.5)
                .foregroundStyle(.tertiary)

            Menu {
                ForEach(tracks) { track in
                    Button {
                        selectedSubtitleTrackID = track.id
                        subtitlesOff = false
                    } label: {
                        if selectedSubtitleTrackID == track.id && !subtitlesOff {
                            Label(track.displayName, systemImage: "checkmark")
                        } else {
                            Text(track.displayName)
                        }
                    }
                }
                Divider()
                Button {
                    subtitlesOff = true
                    selectedSubtitleTrackID = nil
                } label: {
                    if subtitlesOff {
                        Label("Off", systemImage: "checkmark")
                    } else {
                        Text("Off")
                    }
                }
            } label: {
                settingsPickerLabel(subtitleDisplayLabel(tracks: tracks))
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func audioTrackPicker(tracks: [PlaybackCoreDomain.AudioTrack]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Audio Track")
                .font(DesignTokens.Typography.sectionHeader)
                .textCase(.uppercase)
                .tracking(1.5)
                .foregroundStyle(.tertiary)

            Menu {
                ForEach(tracks) { track in
                    Button {
                        selectedAudioTrackID = track.id
                    } label: {
                        if selectedAudioTrackID == track.id {
                            Label(track.displayName, systemImage: "checkmark")
                        } else {
                            Text(track.displayName)
                        }
                    }
                }
            } label: {
                settingsPickerLabel(audioDisplayLabel(tracks: tracks))
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func hdrOutputToggle(hdrType: PlaybackCoreDomain.HDRType) -> some View {
        let hdrLabel = PlaybackInfoFormatter.hdrTypeLabel(hdrType)
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("HDR Output")
                    .font(.body)
                Text("Enabled by default")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: $hdrOutputEnabled)
                .labelsHidden()
                .accessibilityIdentifier("videoDetail.hdrToggle")
                .accessibilityLabel("\(hdrLabel) Output")
        }
        .padding(12)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: DesignTokens.Radius.badge, style: .continuous))
    }

    // MARK: - Playback Mode Picker

    @ViewBuilder
    private func playbackModePickerSection(prepared: PreparedPlayback) -> some View {
        let projectionType = prepared.metadata?.mediaProfile?.projectionType
        let allowedModes = DecidePlaybackModeUseCase.allowedModes(for: projectionType)

        VStack(alignment: .leading, spacing: 4) {
            Text("Playback Mode")
                .font(DesignTokens.Typography.sectionHeader)
                .textCase(.uppercase)
                .tracking(1.5)
                .foregroundStyle(.tertiary)

            HStack(spacing: 8) {
                ForEach(PlaybackMode.allCases, id: \.self) { mode in
                    playbackModeButton(mode: mode, allowedModes: allowedModes)
                }
            }
            .accessibilityIdentifier("videoDetail.playbackModePicker")
        }
        .padding(12)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: DesignTokens.Radius.badge, style: .continuous))
        .onAppear {
            selectedPlaybackMode = appModel.playbackMode
        }
    }

    @ViewBuilder
    private func playbackModeButton(mode: PlaybackMode, allowedModes: Set<PlaybackMode>) -> some View {
        let isAllowed = allowedModes.contains(mode)
        let isSelected = selectedPlaybackMode == mode
        let bgColor: Color = isSelected ? Color.enchronPrimary.opacity(0.25) : Color.white.opacity(0.04)
        let borderColor: Color = isSelected ? Color.enchronPrimary.opacity(0.5) : Color.clear
        let fgStyle: Color = isAllowed ? (isSelected ? Color.enchronPrimary : Color.primary) : Color.secondary

        Button {
            selectedPlaybackMode = mode
        } label: {
            HStack(spacing: 6) {
                Image(systemName: playbackModeIcon(mode))
                    .font(.caption)
                Text(playbackModeLabel(mode))
                    .font(.caption.weight(.semibold))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(bgColor, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.badge, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.badge, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: 0.5)
            )
            .foregroundStyle(fgStyle)
        }
        .buttonStyle(.plain)
        .disabled(!isAllowed)
        .accessibilityIdentifier("videoDetail.playbackModePicker.\(mode.rawValue)")
        .accessibilityLabel(playbackModeLabel(mode))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
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

    @ViewBuilder
    private func settingsPickerLabel(_ text: String) -> some View {
        HStack {
            Text(text)
                .font(.body)
            Spacer()
            Image(systemName: "chevron.up.chevron.down")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: DesignTokens.Radius.badge, style: .continuous))
    }

    // MARK: - Track Selection Helpers

    private func initializeTrackSelections(prepared: PreparedPlayback) {
        if selectedAudioTrackID == nil {
            selectedAudioTrackID = prepared.audioTracks.first(where: { $0.isDefault })?.id
                ?? prepared.audioTracks.first?.id
        }
        if selectedSubtitleTrackID == nil && !subtitlesOff {
            if let defaultSub = prepared.subtitleTracks.first(where: { $0.isDefault }) {
                selectedSubtitleTrackID = defaultSub.id
            }
        }
    }

    private func subtitleDisplayLabel(tracks: [PlaybackCoreDomain.SubtitleTrack]) -> String {
        if subtitlesOff { return "Off" }
        if let id = selectedSubtitleTrackID,
           let track = tracks.first(where: { $0.id == id }) {
            return track.displayName
        }
        return tracks.first(where: { $0.isDefault })?.displayName ?? tracks.first?.displayName ?? "None"
    }

    private func audioDisplayLabel(tracks: [PlaybackCoreDomain.AudioTrack]) -> String {
        if let id = selectedAudioTrackID,
           let track = tracks.first(where: { $0.id == id }) {
            return track.displayName
        }
        return tracks.first(where: { $0.isDefault })?.displayName ?? tracks.first?.displayName ?? "None"
    }

    private func confirmWithSelections(_ prepared: PreparedPlayback, resumePosition: Double? = nil) {
        coordinator.confirmPlayback(
            prepared,
            resumePosition: resumePosition,
            selectedAudioTrackID: selectedAudioTrackID,
            selectedSubtitleTrackID: selectedSubtitleTrackID,
            subtitlesOff: subtitlesOff,
            hdrEnabled: hdrOutputEnabled
        )
        // Apply user's playback mode selection after confirmation
        // (set after confirmPlayback to override autoRoutePlaybackMode)
        let chosenMode = selectedPlaybackMode
        let projectionType = prepared.metadata?.mediaProfile?.projectionType
        let allowedModes = DecidePlaybackModeUseCase.allowedModes(for: projectionType)
        if allowedModes.contains(chosenMode) {
            appModel.updatePlaybackMode(chosenMode)
        }
        dismiss()
    }

    private func projectionLabel(_ type: PlaybackCoreDomain.ProjectionType) -> String {
        switch type {
        case .flat:
            return "Flat"
        case .equirectangular360:
            return "360\u{00B0}"
        case .equirectangular180:
            return "180\u{00B0} VR"
        case .fisheye:
            return "Fisheye"
        }
    }
}

// MARK: - Track Display Protocol

/// Unifies AudioTrack and SubtitleTrack for the track list UI.
protocol TrackDisplayable {
    var displayName: String { get }
    var languageCode: String? { get }
    var isDefault: Bool { get }
}

extension PlaybackCoreDomain.AudioTrack: TrackDisplayable {}
extension PlaybackCoreDomain.SubtitleTrack: TrackDisplayable {}
