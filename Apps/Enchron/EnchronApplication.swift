import Foundation
import MediaLibrary
import MediaSource
import Observation
import PlaybackFeature
import PlaybackPresentation
import PlaybackCore
@preconcurrency import Photos
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
        let defaultsSuiteName = isUITesting ? "app.enchron.ui-testing" : nil
        let defaults: UserDefaults
        if let defaultsSuiteName {
            defaults = UserDefaults(suiteName: defaultsSuiteName) ?? .standard
            defaults.removePersistentDomain(forName: defaultsSuiteName)
        } else {
            defaults = .standard
        }
        if environment["ENCHRON_RESET_MEDIA_LIBRARY"] == "1" {
            defaults.removeObject(forKey: "enchron.mediaLibrary")
        }

        let screenPositionStore = PlaybackPresentationStorage.makeScreenPositionStore(
            suiteName: defaultsSuiteName
        )
        let playbackSpeedOverride = environment["ENCHRON_PLAYBACK_SPEED_OVERRIDE"].flatMap(Double.init)
            .map { PlaybackModel.PlaybackSpeed($0).value }
        let preferencesStore = UserDefaultsStore(
            defaults: defaults,
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
            mediaStateSuiteName: defaultsSuiteName,
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
        let mediaLibraryFeature = MediaLibraryFeature(
            sourceMode: isUITesting ? .uiTestFixture(sourceID: fixtureSourceID) : .production,
            defaultsSuiteName: defaultsSuiteName,
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
        playbackRuntime.setSessionLifecycleHandler {
            [weak spatialPlatformEffectCoordinator] event in
            spatialPlatformEffectCoordinator?.playbackSessionLifecycleChanged(event)
        }
        #endif
        fileBrowsingViewModel = browser
        mediaLibraryViewModel = mediaLibrary
        playbackLauncher = launcher
        settingsViewModel = SettingsViewModel(store: preferencesStore)
        thumbnailService = .shared

        Self.beginAutoplayIfRequested(
            environment: environment,
            isUITesting: isUITesting,
            mediaLibrary: mediaLibrary,
            launcher: launcher
        )
        Self.beginPhotoAutoplayIfRequested(
            environment: environment,
            mediaLibrary: mediaLibrary
        )
    }

    @MainActor
    private static func beginAutoplayIfRequested(
        environment: [String: String],
        isUITesting: Bool,
        mediaLibrary: MediaLibraryViewModel,
        launcher: PlaybackLaunchCoordinator
    ) {
        guard let source = environment["ENCHRON_AUTOPLAY_FILE"], source.isEmpty == false else {
            return
        }
        Task { @MainActor in
            let url: URL
            if let parsedURL = URL(string: source), parsedURL.scheme?.isEmpty == false {
                url = parsedURL
            } else {
                url = URL(fileURLWithPath: source)
            }
            if isUITesting || !url.isFileURL {
                launcher.requestPlayback(
                    PlaybackLaunchRequest(url: url, displayName: url.lastPathComponent)
                )
                return
            }
            mediaLibrary.addFiles([url])
            guard let reference = mediaLibrary.references.first(where: {
                $0.name == url.lastPathComponent
            }) else {
                mediaLibrary.lastErrorMessage =
                    "The verification media could not be added to Media Library."
                return
            }
            mediaLibrary.play(reference)
        }
    }

    @MainActor
    private static func beginPhotoAutoplayIfRequested(
        environment: [String: String],
        mediaLibrary: MediaLibraryViewModel
    ) {
        guard environment["ENCHRON_AUTOPLAY_FIRST_PHOTO"] == "1" else { return }
        Task { @MainActor in
            let authorization = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            guard authorization == .authorized || authorization == .limited else {
                mediaLibrary.lastErrorMessage =
                    "Photos Full Access is required for automated playback verification."
                return
            }
            guard let asset = PHAsset.fetchAssets(with: .video, options: nil).firstObject else {
                mediaLibrary.lastErrorMessage =
                    "No Photos video is available for automated playback verification."
                return
            }
            let name = PHAssetResource.assetResources(for: asset).first?.originalFilename
                ?? "Photos Video"
            mediaLibrary.addPhotoItems([(asset.localIdentifier, name)])
            guard let reference = mediaLibrary.references.last else {
                mediaLibrary.lastErrorMessage =
                    "The Photos video reference could not be created."
                return
            }
            mediaLibrary.play(reference)
        }
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
            sourceAccess: accessLease
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
