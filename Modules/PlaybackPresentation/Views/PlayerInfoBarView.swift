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
                immersiveEntryTarget: playbackRuntime.canEnterSpatialPresentation
                    ? appModel.playbackPresentation.enterImmersiveTarget
                    : nil,
                canApplyFormat: playbackRuntime.canEnterSpatialPresentation,
                mediaFormatProvenance: playbackRuntime.activeMediaFormatProvenance,
                sourceMediaFormatSummary: playbackRuntime.sourceMediaFormatSummary,
                projection: playbackRuntime.effectiveProjectionType,
                horizontalFieldOfViewDegrees:
                    playbackRuntime.effectiveHorizontalFieldOfViewDegrees,
                stereoLayout: playbackRuntime.effectiveStereoLayout,
                defaultScenicEnvironment: appModel.defaultScenicEnvironment,
                onEnterImmersive: enterImmersive,
                onApplyFormat: applyFormat,
                onRestoreAutomaticFormat: restoreAutomaticFormat,
                onSecondaryMenuVisibilityChange: onSecondaryMenuVisibilityChange
            )
        } moreControl: {
            ProductionPlaybackMoreMenu()
        }
    }

    private var initialPresentedMenu: PlaybackTopSecondaryMenu? {
        let environment = ProcessInfo.processInfo.environment
        guard environment["ENCHRON_UI_TESTING"] == "1",
              let rawValue = environment["ENCHRON_UI_INITIAL_MENU"] else { return nil }
        return PlaybackTopSecondaryMenu(rawValue: rawValue)
    }

    private func enterImmersive(
        environment: SpatialSceneDomain.CinemaEnvironment?,
        effect: SpatialSceneDomain.EnvironmentEffect?
    ) {
        appModel.registerControlsInteraction()
        guard playbackRuntime.canEnterSpatialPresentation,
              let target = appModel.playbackPresentation.enterImmersiveTarget else { return }
        do {
            _ = try appModel.requestPlaybackPresentation(
                target,
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
