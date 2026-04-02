import SwiftUI

/// Shows media metadata and track selection before the user confirms playback.
///
/// Observes `PlaybackLaunchCoordinator.currentPreparation` to progressively
/// reveal metadata as it resolves. The user can select audio/subtitle tracks
/// and tap Play to confirm, or navigate back to cancel.
public struct VideoDetailView: View {
    @Environment(PlaybackLaunchCoordinator.self) private var coordinator
    @Environment(FileBrowsingViewModel.self) private var fileBrowsingViewModel
    @Environment(AppModel.self) private var appModel

    @State private var savedProgress: PersistenceDomain.PlaybackProgress?
    @State private var resumePolicy: PersistenceDomain.ResumePolicy = .askEveryTime

    public init() {}

    public var body: some View {
        Group {
            switch coordinator.currentPreparation {
            case .preparing(let request, let metadata):
                preparingContent(request: request, metadata: metadata)

            case .ready(let prepared):
                readyContent(prepared: prepared)

            case .failed(let error):
                failedContent(error: error)

            case nil:
                // Preparation was cancelled or confirmed externally
                ContentUnavailableView("No Video Selected", systemImage: "film")
            }
        }
        .navigationTitle(currentDisplayName)
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            // If preparation is still active when view disappears (back navigation),
            // cancel it. confirmPlayback already clears currentPreparation before
            // dismissal, so this only fires for back-navigation.
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
        ScrollView {
            VStack(spacing: 24) {
                headerSection(displayName: request.displayName)

                if let metadata {
                    metadataSection(metadata: metadata)
                }

                ProgressView("Loading media information...")
                    .padding(.top, 20)

                playButton(enabled: false)
            }
            .padding()
        }
    }

    // MARK: - Ready State

    @ViewBuilder
    private func readyContent(prepared: PreparedPlayback) -> some View {
        ScrollView {
            VStack(spacing: 24) {
                headerSection(displayName: prepared.request.displayName)

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

                playbackButtons(prepared: prepared)
            }
            .padding()
        }
        .task {
            guard let fileID = prepared.request.fileIdentifier else { return }
            savedProgress = await coordinator.loadProgress(for: fileID)
            resumePolicy = coordinator.currentResumePolicy()
        }
    }

    @ViewBuilder
    private func playbackButtons(prepared: PreparedPlayback) -> some View {
        if let progress = savedProgress, progress.position.seconds > 5 {
            switch resumePolicy {
            case .askEveryTime:
                VStack(spacing: 12) {
                    Button {
                        coordinator.confirmPlayback(prepared, resumePosition: progress.position.seconds)
                        fileBrowsingViewModel.detailNavigationRequest = nil
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
                        fileBrowsingViewModel.detailNavigationRequest = nil
                    } label: {
                        Label("Play from Start", systemImage: "arrow.counterclockwise")
                            .font(.body)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Play from start")
                }
                .padding(.top, 8)

            case .alwaysResume:
                playButton(enabled: true) {
                    coordinator.confirmPlayback(prepared, resumePosition: progress.position.seconds)
                    fileBrowsingViewModel.detailNavigationRequest = nil
                }

            case .alwaysStartFromBeginning:
                playButton(enabled: true) {
                    coordinator.confirmPlayback(prepared)
                    fileBrowsingViewModel.detailNavigationRequest = nil
                }
            }
        } else {
            playButton(enabled: true) {
                coordinator.confirmPlayback(prepared)
                fileBrowsingViewModel.detailNavigationRequest = nil
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
            Button("Go Back") {
                coordinator.cancelPreparedPlayback()
                fileBrowsingViewModel.detailNavigationRequest = nil
            }
        }
    }

    // MARK: - Shared Components

    @ViewBuilder
    private func headerSection(displayName: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "film")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text(displayName)
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)
                .lineLimit(3)
        }
        .padding(.top, 12)
    }

    @ViewBuilder
    private func metadataSection(metadata: PlaybackMediaMetadata) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Media Info")
                .font(.headline)

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), alignment: .leading),
                    GridItem(.flexible(), alignment: .leading),
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
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

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
        .padding(.top, 8)
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
