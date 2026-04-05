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
    @Environment(\.dismiss) private var dismiss

    @AccessibilityFocusState private var isTitleFocused: Bool
    @State private var savedProgress: PersistenceDomain.PlaybackProgress?
    @State private var resumePolicy: PersistenceDomain.ResumePolicy = .askEveryTime

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
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
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

    // MARK: - Preparing State

    @ViewBuilder
    private func preparingContent(
        request: PlaybackLaunchRequest,
        metadata: PlaybackMediaMetadata?
    ) -> some View {
        GeometryReader { proxy in
            let leftWidth = min(max(proxy.size.width * 0.45, 300), 440)
            HStack(alignment: .top, spacing: 40) {
                // Left column: preview + environment selector + loading play
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        videoPreviewPlaceholder(displayName: request.displayName)
                        environmentSelector()
                        playButton(enabled: false)
                    }
                }
                .frame(width: leftWidth)

                // Right column: metadata (partial) + loading indicator
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if let metadata {
                            metadataSection(metadata: metadata)
                        }
                        ProgressView("Loading media information...")
                            .padding(.top, 8)
                        Spacer(minLength: 0)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    // MARK: - Ready State

    @ViewBuilder
    private func readyContent(prepared: PreparedPlayback) -> some View {
        GeometryReader { proxy in
            let leftWidth = min(max(proxy.size.width * 0.45, 300), 440)
            HStack(alignment: .top, spacing: 40) {
                // Left column: preview + environment selector + resume/play
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        videoPreviewPlaceholder(displayName: prepared.request.displayName)
                        environmentSelector()
                        playbackButtons(prepared: prepared)
                    }
                }
                .frame(width: leftWidth)

                // Right column: metadata + tracks
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if let metadata = prepared.metadata {
                            metadataSection(metadata: metadata)
                        }

                        if !prepared.audioTracks.isEmpty {
                            trackSection(
                                title: "Audio Tracks",
                                icon: "speaker.wave.2",
                                tracks: prepared.audioTracks
                            )
                        }

                        if !prepared.subtitleTracks.isEmpty {
                            trackSection(
                                title: "Subtitles",
                                icon: "captions.bubble",
                                tracks: prepared.subtitleTracks
                            )
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .task {
            guard let fileID = prepared.request.fileIdentifier else { return }
            savedProgress = await coordinator.loadProgress(for: fileID)
            resumePolicy = coordinator.currentResumePolicy()
        }
    }

    // MARK: - Playback Buttons

    @ViewBuilder
    private func playbackButtons(prepared: PreparedPlayback) -> some View {
        if let progress = savedProgress, progress.position.seconds > 5 {
            switch resumePolicy {
            case .askEveryTime:
                VStack(spacing: 12) {
                    Button {
                        coordinator.confirmPlayback(prepared, resumePosition: progress.position.seconds)
                        dismiss()
                    } label: {
                        Label("Resume from \(Self.formatTime(progress.position.seconds))", systemImage: "play.fill")
                            .font(.title3.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.accentColor)
                    .accessibilityLabel("Resume from \(Self.formatTime(progress.position.seconds))")

                    Button {
                        coordinator.confirmPlayback(prepared)
                        dismiss()
                    } label: {
                        Label("Play from Start", systemImage: "arrow.counterclockwise")
                            .font(.body)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Play from start")
                }

            case .alwaysResume:
                playButton(enabled: true) {
                    coordinator.confirmPlayback(prepared, resumePosition: progress.position.seconds)
                    dismiss()
                }

            case .alwaysStartFromBeginning:
                playButton(enabled: true) {
                    coordinator.confirmPlayback(prepared)
                    dismiss()
                }
            }
        } else {
            playButton(enabled: true) {
                coordinator.confirmPlayback(prepared)
                dismiss()
            }
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

    // MARK: - Video Preview

    @ViewBuilder
    private func videoPreviewPlaceholder(displayName: String) -> some View {
        VStack(spacing: 12) {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.card, style: .continuous)
                .fill(.quaternary)
                .aspectRatio(16/9, contentMode: .fit)
                .overlay {
                    Image(systemName: "film")
                        .font(DesignTokens.SymbolSize.hero)
                        .foregroundStyle(.secondary)
                }

            Text(displayName)
                .font(.title3.weight(.semibold))
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Environment Selector

    @ViewBuilder
    private func environmentSelector() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Cinema Environment")
                .font(.headline)

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
                                    .frame(width: 100, height: 64)
                                    .overlay {
                                        Image(systemName: environmentIcon(env))
                                            .font(.title2)
                                            .foregroundStyle(isSelected ? .primary : .secondary)
                                    }
                                    .overlay(
                                        RoundedRectangle(cornerRadius: DesignTokens.Radius.badge, style: .continuous)
                                            .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2)
                                    )

                                Text(env.displayName)
                                    .font(.caption)
                                    .foregroundStyle(isSelected ? .primary : .secondary)
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
        }
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
        VStack(alignment: .leading, spacing: 12) {
            Text("Media Info")
                .font(.headline)

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), alignment: .leading),
                    GridItem(.flexible(), alignment: .leading)
                ],
                spacing: 10
            ) {
                if let profile = metadata.mediaProfile {
                    metadataRow(
                        label: "Resolution",
                        value: "\(profile.resolution.width) \u{00D7} \(profile.resolution.height)"
                    )

                    metadataRow(
                        label: "HDR",
                        value: PlaybackInfoFormatter.hdrTypeLabel(profile.hdrType)
                    )

                    metadataRow(
                        label: "Codec",
                        value: PlaybackInfoFormatter.videoCodecLabel(profile.videoCodec)
                    )

                    metadataRow(
                        label: "Duration",
                        value: PlaybackInfoFormatter.duration(profile.durationSeconds)
                    )

                    metadataRow(
                        label: "Frame Rate",
                        value: PlaybackInfoFormatter.frameRate(profile.frameRate)
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
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.card, style: .continuous))
    }

    @ViewBuilder
    private func metadataRow(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.body)
        }
    }

    // MARK: - Track Section

    @ViewBuilder
    private func trackSection<T: Identifiable>(
        title: String,
        icon: String,
        tracks: [T]
    ) -> some View where T: TrackDisplayable {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.headline)

            ForEach(tracks) { track in
                HStack {
                    Text(track.displayName)
                        .font(.body)

                    Spacer()

                    if let lang = track.languageCode {
                        Text(lang.uppercased())
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(.quaternary, in: Capsule())
                    }

                    if track.isDefault {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.card, style: .continuous))
    }

    // MARK: - Play Button

    @ViewBuilder
    private func playButton(enabled: Bool, action: (() -> Void)? = nil) -> some View {
        Button {
            action?()
        } label: {
            Label("Play", systemImage: "play.fill")
                .font(.title3.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        }
        .buttonStyle(.borderedProminent)
        .tint(.accentColor)
        .disabled(!enabled)
        .accessibilityLabel("Play")
    }

    private func projectionLabel(_ type: PlaybackCoreDomain.ProjectionType) -> String {
        switch type {
        case .flat:
            return "Flat"
        case .stereoscopicSBS:
            return "3D Side-by-Side"
        case .stereoscopicOU:
            return "3D Over-Under"
        case .panorama360:
            return "360\u{00B0}"
        case .panorama180:
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
