import Foundation
import MediaLibrary
import MediaSource
import Observation
import PlaybackFeature
import PlaybackPresentation
import PlaybackCore
import SwiftUI

@MainActor
@Observable
final class EnchronApplication {
    let appModel: AppModel
    let playbackRuntime: PlaybackRuntime
    let fileBrowsingViewModel: FileBrowsingViewModel
    let mediaLibraryViewModel: MediaLibraryViewModel
    let playbackLauncher: PlaybackLaunchCoordinator
    let settingsViewModel: SettingsViewModel
    let thumbnailService: ThumbnailService
    #if os(visionOS)
    let spatialPlatformEffectCoordinator: SpatialPlatformEffectCoordinator
    #endif

    init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        let isUITesting = environment["ENCHRON_UI_TESTING"] == "1"
        let mediaLibraryDefaultsSuiteName = isUITesting ? "app.enchron.ui-testing" : nil
        let regressionPreferencesSuiteName = environment[
            "ENCHRON_DEVICE_REGRESSION_PREFERENCES_SUITE"
        ].flatMap { value in
            value == "app.enchron.device-regression" ? value : nil
        }
        let preferencesSuiteName = isUITesting
            ? "app.enchron.ui-testing"
            : regressionPreferencesSuiteName
        let mediaStateSuiteName = Self.mediaStateSuiteName(
            isUITesting: isUITesting,
            environment: environment
        )
        let preferencesDefaults: UserDefaults
        if let preferencesSuiteName {
            preferencesDefaults = UserDefaults(suiteName: preferencesSuiteName) ?? .standard
            if isUITesting {
                preferencesDefaults.removePersistentDomain(forName: preferencesSuiteName)
            } else if let resetToken = environment[
                "ENCHRON_DEVICE_REGRESSION_PREFERENCES_RESET_TOKEN"
            ], preferencesDefaults.string(
                forKey: "enchron.deviceRegressionPreferencesResetToken"
            ) != resetToken {
                preferencesDefaults.removePersistentDomain(forName: preferencesSuiteName)
                preferencesDefaults.set(
                    resetToken,
                    forKey: "enchron.deviceRegressionPreferencesResetToken"
                )
            }
        } else {
            preferencesDefaults = .standard
        }
        if let mediaStateSuiteName,
           mediaStateSuiteName != preferencesSuiteName {
            // Spatial acceptance uses the production Media Library, but must
            // start without a previous run's playback position or format.
            UserDefaults(suiteName: mediaStateSuiteName)?
                .removePersistentDomain(forName: mediaStateSuiteName)
        }

        let screenPositionStore = PlaybackPresentationStorage.makeScreenPositionStore(
            suiteName: preferencesSuiteName
        )
        let playbackSpeedOverride = environment["ENCHRON_PLAYBACK_SPEED_OVERRIDE"].flatMap(Double.init)
            .map { PlaybackModel.PlaybackSpeed($0).value }
        let preferencesStore = UserDefaultsStore(
            defaults: preferencesDefaults,
            playbackSpeedOverride: playbackSpeedOverride
        )
        if isUITesting {
            preferencesStore.savePreferences(
                .init(resumePolicy: .alwaysStartFromBeginning)
            )
        }
        let appModel = AppModel(
            playbackPresentationModel: PlaybackPresentationModel(
                screenPositionStore: screenPositionStore
            )
        )
        let playbackRuntime = PlaybackRuntime()
        let launcher = PlaybackLaunchCoordinator(
            playbackRuntime: playbackRuntime,
            mediaStateSuiteName: mediaStateSuiteName,
            preferencesProvider: preferencesStore
        )
        launcher.onResolvedLaunchFormatApplied = { [weak appModel] format in
            guard let appModel,
                  appModel.pendingSpatialPlatformEffect == nil else { return }
            if format.projection.isPanoramic {
                switch appModel.playbackPresentation {
                case .window:
                    _ = try? appModel.requestPlaybackPresentation(
                        .panorama,
                        mediaSessionID: playbackRuntime.activeSessionID,
                        wasPlaying: playbackRuntime.productLifecycle == .playing
                    )
                case .docked:
                    appModel.setAutomaticPanoramaEntryPending(true)
                    _ = try? appModel.requestPlaybackPresentation(
                        .window,
                        mediaSessionID: playbackRuntime.activeSessionID,
                        wasPlaying: playbackRuntime.productLifecycle == .playing
                    )
                case .panorama:
                    appModel.setAutomaticPanoramaEntryPending(false)
                }
            } else {
                appModel.setAutomaticPanoramaEntryPending(false)
                if appModel.playbackPresentation == .panorama {
                    _ = try? appModel.requestPlaybackPresentation(
                        .window,
                        mediaSessionID: playbackRuntime.activeSessionID,
                        wasPlaying: playbackRuntime.productLifecycle == .playing
                    )
                }
            }
        }
        let fixtureSourceID = UUID(uuidString: "00000000-0000-0000-0000-000000000101")!
        let uiTestDataset = environment["ENCHRON_UI_TEST_LIBRARY_DATASET"]
            .flatMap(MediaLibraryFeature.UITestDataset.init(rawValue:))
            ?? .standard
        let mediaLibraryFeature = MediaLibraryFeature(
            sourceMode: isUITesting
                ? .uiTestFixture(sourceID: fixtureSourceID, dataset: uiTestDataset)
                : .production,
            defaultsSuiteName: mediaLibraryDefaultsSuiteName,
            viewingStateProvider: Self.viewingStateProvider(launcher),
            onPlay: { launcher.requestPlayback($0.playbackLaunchRequest) }
        )
        let mediaLibrary = mediaLibraryFeature.library
        let browser = mediaLibraryFeature.browser

        launcher.nextFileProvider = { [weak mediaLibrary, weak browser, weak playbackRuntime] in
            switch playbackRuntime?.currentLaunchRequest?.collectionOrigin {
            case .mediaLibrary:
                return await mediaLibrary?.nextPlaybackItem()?.playbackLaunchRequest
            case .sourceDirectory:
                return await browser?.nextPlaybackItem()?.playbackLaunchRequest
            case .standalone, nil:
                return nil
            }
        }
        launcher.playbackQueueProvider = { [weak mediaLibrary, weak browser, weak playbackRuntime] in
            switch playbackRuntime?.currentLaunchRequest?.collectionOrigin {
            case .mediaLibrary:
                return mediaLibrary?.mediaCollectionSnapshot.playbackQueueSnapshot ?? .empty
            case .sourceDirectory:
                return browser?.mediaCollectionSnapshot.playbackQueueSnapshot ?? .empty
            case .standalone, nil:
                return .empty
            }
        }
        launcher.queueSelectionProvider = { [weak mediaLibrary, weak browser, weak playbackRuntime] id in
            switch playbackRuntime?.currentLaunchRequest?.collectionOrigin {
            case .mediaLibrary:
                return await mediaLibrary?.playbackItem(forCollectionItemID: id)?.playbackLaunchRequest
            case .sourceDirectory:
                return await browser?.playbackItem(forCollectionItemID: id)?.playbackLaunchRequest
            case .standalone, nil:
                return nil
            }
        }
        launcher.onViewingStatesCleared = { [weak mediaLibrary, weak browser] in
            mediaLibrary?.refreshViewingStates()
            browser?.refreshViewingStates()
        }

        let preferences = preferencesStore.loadPreferences()
        if let override = environment["ENCHRON_CONTROLS_AUTO_HIDE_SECONDS"].flatMap(Int.init),
           override > 0 {
            appModel.controlsAutoHideSeconds = override
        } else {
            appModel.controlsAutoHideSeconds = preferences.controlsAutoHideSeconds
        }
        let configuredEnvironment = SpatialSceneDomain.CinemaEnvironment(
            preferenceValue: preferences.defaultEnvironmentID
        ) ?? appModel.currentCinemaEnvironment
        appModel.configureDefaultEnvironment(configuredEnvironment)

        self.appModel = appModel
        self.playbackRuntime = playbackRuntime
        #if os(visionOS)
        let spatialPlatformEffectCoordinator = SpatialPlatformEffectCoordinator(
            appModel: appModel,
            playbackRuntime: playbackRuntime
        )
        self.spatialPlatformEffectCoordinator = spatialPlatformEffectCoordinator
        playbackRuntime.setSessionLifecycleHandler { [weak spatialPlatformEffectCoordinator] event in
            spatialPlatformEffectCoordinator?.playbackSessionLifecycleChanged(event)
        }
        #endif
        fileBrowsingViewModel = browser
        mediaLibraryViewModel = mediaLibrary
        playbackLauncher = launcher
        settingsViewModel = SettingsViewModel(store: preferencesStore)
        thumbnailService = .shared
    }

    static func mediaStateSuiteName(
        isUITesting: Bool,
        environment: [String: String]
    ) -> String? {
        if isUITesting {
            return "app.enchron.ui-testing"
        }
        guard environment["ENCHRON_SPATIAL_ACCEPTANCE"] == "1",
              environment["ENCHRON_TEST_MEDIA_STATE_SUITE"] == "1" else {
            return nil
        }
        return "app.enchron.spatial-acceptance"
    }

    private static func viewingStateProvider(
        _ launcher: PlaybackLaunchCoordinator
    ) -> MediaViewingStateProvider {
        { identity in
            switch await launcher.viewingState(for: identity) {
            case .resumable(let position, let duration):
                VideoCardViewingState(
                    positionSeconds: position,
                    durationSeconds: duration,
                    isCompleted: false
                )
            case .completed(let duration):
                VideoCardViewingState(
                    positionSeconds: duration,
                    durationSeconds: duration,
                    isCompleted: true
                )
            case nil:
                nil
            }
        }
    }
}

private extension MediaPlaybackItem {
    var playbackLaunchRequest: PlaybackLaunchRequest {
        let playbackOrigin: PlaybackCollectionOrigin = switch collectionOrigin {
        case .standalone: .standalone
        case .mediaLibrary: .mediaLibrary
        case .sourceDirectory: .sourceDirectory
        }
        return PlaybackLaunchRequest(
            url: url,
            displayName: displayName,
            fileIdentifier: stableIdentifier.map(PlaybackFileIdentifier.init(rawValue:)),
            initialMetadata: PlaybackMediaMetadata(fileSizeInBytes: sizeInBytes),
            collectionOrigin: playbackOrigin,
            versionedIdentity: versionedIdentity,
            sourceAccess: accessLease,
            externalSubtitleSources: externalSubtitleSources,
            externalSubtitleErrorMessage: externalSubtitleErrorMessage
        )
    }
}

private extension MediaCollectionSnapshot {
    var playbackQueueSnapshot: PlaybackQueueSnapshot {
        PlaybackQueueSnapshot(entries: entries.map {
            PlaybackQueueEntry(id: $0.id, displayName: $0.displayName, isCurrent: $0.isCurrent)
        })
    }
}

extension View {
    func enchronEnvironment(_ application: EnchronApplication) -> some View {
        environment(application.appModel)
            .environment(application.playbackRuntime)
            #if os(visionOS)
            .environment(application.spatialPlatformEffectCoordinator)
            #endif
            .environment(application.fileBrowsingViewModel)
            .environment(application.mediaLibraryViewModel)
            .environment(application.playbackLauncher)
            .environment(application.settingsViewModel)
            .environment(application.thumbnailService)
    }
}
