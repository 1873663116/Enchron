import DesignSystem
import PlaybackFeature
import PlaybackPresentation
import SwiftUI

/// Window playback chrome. Navigation and presentation actions stay over the
/// video while media information belongs to the bottom Player Controls ornament.
struct PlayerInfoBarView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(PlaybackRuntime.self) private var playbackRuntime
    @Environment(PlaybackLaunchCoordinator.self) private var launcher

    var onSecondaryMenuVisibilityChange: ((Bool) -> Void)?

    var body: some View {
        WindowPlaybackTopChrome {
            GlassCircleIconButton.back(
                accessibilityLabel: "Back",
                action: {
                    launcher.stopPlayback()
                },
                accessibilityIdentifier: "PlayerUI-InfoBar-button-back"
            )
            .keyboardShortcut("[", modifiers: .command)
            .accessibilityHint("Stops playback and returns to browser")
        } spatialActions: {
            PlaybackTopActions(
                initialPresentedMenu: initialPresentedMenu,
                canDock: playbackRuntime.canEnterSpatialPresentation
                    && PlaybackPresentationAvailability.canDock(
                        in: appModel.playbackPresentation,
                        isPanoramic: playbackRuntime.effectiveContentIsPanoramic
                    ),
                canApplyFormat: playbackRuntime.canEnterSpatialPresentation,
                resumesPanorama: PlaybackPresentationAvailability.windowShowsPanoramaResume(
                    in: appModel.playbackPresentation,
                    isPanoramic: playbackRuntime.effectiveContentIsPanoramic
                ),
                mediaFormatProvenance: playbackRuntime.activeMediaFormatProvenance,
                sourceMediaFormatSummary: playbackRuntime.sourceMediaFormatSummary,
                projection: playbackRuntime.effectiveProjectionType,
                horizontalFieldOfViewDegrees:
                    playbackRuntime.effectiveHorizontalFieldOfViewDegrees,
                stereoLayout: playbackRuntime.effectiveStereoLayout,
                defaultScenicEnvironment: appModel.defaultScenicEnvironment,
                onDock: dock,
                onApplyFormat: applyFormat,
                onRestoreAutomaticFormat: restoreAutomaticFormat,
                onResumePanorama: resumePanorama,
                onSecondaryMenuVisibilityChange: onSecondaryMenuVisibilityChange
            )
        } moreControl: {
            ProductionPlaybackMoreMenu()
        }
    }

    private func resumePanorama() {
        appModel.registerControlsInteraction()
        guard playbackRuntime.canEnterSpatialPresentation,
              playbackRuntime.effectiveContentIsPanoramic else { return }
        do {
            _ = try appModel.requestPlaybackPresentation(
                .panorama,
                mediaSessionID: playbackRuntime.activeSessionID,
                wasPlaying: playbackRuntime.productLifecycle == .playing
            )
        } catch {
            playbackRuntime.lastErrorMessage = error.localizedDescription
        }
    }

    private var initialPresentedMenu: PlaybackTopSecondaryMenu? {
        let environment = ProcessInfo.processInfo.environment
        guard environment["ENCHRON_UI_TESTING"] == "1",
              let rawValue = environment["ENCHRON_UI_INITIAL_MENU"] else { return nil }
        return PlaybackTopSecondaryMenu(rawValue: rawValue)
    }

    private func dock(
        in environment: SpatialSceneDomain.CinemaEnvironment,
        effect: SpatialSceneDomain.EnvironmentEffect?
    ) {
        guard playbackRuntime.canEnterSpatialPresentation else { return }
        do {
            _ = try appModel.requestPlaybackPresentation(
                .docked,
                environment: environment,
                effect: effect,
                mediaSessionID: playbackRuntime.activeSessionID,
                wasPlaying: playbackRuntime.productLifecycle == .playing
            )
        } catch {
            playbackRuntime.lastErrorMessage = error.localizedDescription
        }
    }

    private func applyFormat(
        _ projection: PlaybackModel.ProjectionType,
        _ horizontalFieldOfViewDegrees: Int?,
        _ stereo: PlaybackModel.StereoLayout
    ) {
        guard playbackRuntime.canEnterSpatialPresentation else { return }
        Task {
            do {
                try await launcher.applyFormat(
                    projection: projection,
                    horizontalFieldOfViewDegrees: horizontalFieldOfViewDegrees,
                    stereo: stereo
                )
            } catch {
                playbackRuntime.lastErrorMessage = error.localizedDescription
            }
        }
    }

    private func restoreAutomaticFormat() {
        guard playbackRuntime.canEnterSpatialPresentation else { return }
        Task {
            do {
                try await launcher.resetFormat()
            } catch {
                playbackRuntime.lastErrorMessage = error.localizedDescription
            }
        }
    }

}
