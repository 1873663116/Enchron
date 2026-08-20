import Foundation
import DesignSystem
import Emby
import MediaLibrary
import MediaSource
import Observation
import OSLog
import PlaybackFeature
import PlaybackPresentation
import PlaybackCore
import SwiftUI
import UIKit

typealias StorageCredential = MediaSource.StorageCredential

enum EffectiveMediaFormatPresentationResolution: Equatable {
    case unchanged
    case switchToPortal
    case returnToWindow
}

enum EffectiveMediaFormatPresentationResolver {
    static func resolve(
        _ interpretation: EffectiveMediaFormatInterpretation,
        from presentation: PlaybackPresentation
    ) -> EffectiveMediaFormatPresentationResolution {
        guard presentation.usesMainWindow else {
            return .unchanged
        }

        if interpretation.isPanoramic {
            return presentation == .window ? .switchToPortal : .unchanged
        }

        return presentation == .portal ? .returnToWindow : .unchanged
    }
}

@MainActor
@Observable
final class EnchronApplication {
    private static let logger = Logger(subsystem: "app.enchron", category: "Application")
    let appModel: AppModel
    let playbackRuntime: PlaybackRuntime
    let playbackVideoEntityStore: PlaybackVideoEntityStore
    let embyNavigationModel: EmbyNavigationModel
    let embySessionViewModel: EmbySessionViewModel
    let embyConnectionViewModel: EmbyConnectionViewModel
    let embyHomeViewModel: EmbyHomeViewModel
    let embySearchViewModel: EmbySearchViewModel
    let fileBrowsingViewModel: FileBrowsingViewModel
    let mediaLibraryViewModel: MediaLibraryViewModel
    let mediaLibraryUIState: MediaLibraryUIState
    let playbackLauncher: PlaybackLaunchCoordinator
    let settingsViewModel: SettingsViewModel
    let certificateTrustPrompt: CertificateTrustPrompt
    let spatialPlatformEffectCoordinator: SpatialPlatformEffectCoordinator

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
           mediaStateSuiteName != preferencesSuiteName,
           let mediaStateDefaults = UserDefaults(suiteName: mediaStateSuiteName) {
            // A spatial acceptance test starts with isolated playback state,
            // but a process relaunch inside that same test must preserve the
            // format it is explicitly verifying. A new reset token marks a
            // new test; the same token marks a cold relaunch within that test.
            let resetToken = environment[
                "ENCHRON_TEST_MEDIA_STATE_RESET_TOKEN"
            ]
            let storedResetTokenKey =
                "enchron.spatialAcceptanceMediaStateResetToken"
            if resetToken == nil
                || mediaStateDefaults.string(forKey: storedResetTokenKey)
                    != resetToken {
                mediaStateDefaults.removePersistentDomain(
                    forName: mediaStateSuiteName
                )
                if let resetToken {
                    mediaStateDefaults.set(
                        resetToken,
                        forKey: storedResetTokenKey
                    )
                }
            }
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
        ArtworkNetworkConfiguration.use(
            session: MediaSourceNetwork.shared.session,
            imageProvider: {
                ArtworkStore.shared.image(for: ArtworkKey(remoteImageURL: $0))
            },
            imageStorer: {
                try ArtworkStore.shared.store($1, for: ArtworkKey(remoteImageURL: $0))
            }
        )
        let certificateTrustPrompt = CertificateTrustPrompt()
        ServerTrustPolicy.shared.approvalHandler = { [weak certificateTrustPrompt] certificate in
            await certificateTrustPrompt?.requestApproval(for: certificate) ?? false
        }
        let playbackVideoEntityStore = PlaybackVideoEntityStore()
        let launcher = PlaybackLaunchCoordinator(
            playbackRuntime: playbackRuntime,
            mediaStateSuiteName: mediaStateSuiteName,
            preferencesProvider: preferencesStore
        )
        let embyClient = EmbyClient(clientIdentity: EmbyClientIdentity(
            name: "Enchron",
            version: Bundle.main.object(
                forInfoDictionaryKey: "CFBundleShortVersionString"
            ) as? String ?? "1",
            deviceName: UIDevice.current.name,
            deviceID: UIDevice.current.identifierForVendor?.uuidString ?? "Enchron-visionOS"
        ))
        let embyNavigation = EmbyNavigationModel()
        let embySession = EmbySessionViewModel(
            client: embyClient,
            navigation: embyNavigation
        )
#if DEBUG
        embySession.diagnosticProbe = {
            AppModel.recordProbe($0, retention: .evidence)
        }
#endif
        let embyConnection = EmbyConnectionViewModel(session: embySession)
        let embyHome = EmbyHomeViewModel(client: embyClient, session: embySession)
        let embySearch = EmbySearchViewModel(client: embyClient, session: embySession)
        launcher.onPlaybackModeEntryStarted = { [weak appModel] mode, isColdLaunch in
            guard let appModel else { return mode }
            appModel.showControls = false
            guard isColdLaunch else {
                return switch appModel.playbackPresentation {
                case .window, .docked: .window
                case .portal, .panorama: .panorama
                }
            }
            let family: PresentationContentFamily = switch mode {
            case .window: .flat
            case .panorama: .panoramic
            }
            appModel.prepareColdPlaybackLaunch(for: family)
            return mode
        }
        launcher.onEffectiveMediaFormatApplied = {
            [weak appModel, weak playbackRuntime] interpretation in
            guard let appModel, let playbackRuntime else { return }
            let resolution = EffectiveMediaFormatPresentationResolver.resolve(
                interpretation,
                from: appModel.playbackPresentation
            )
            do {
                switch resolution {
                case .unchanged:
                    guard playbackRuntime.technicalSessionFormatReplacementIsPending else {
                        return
                    }
                    Task { @MainActor [weak appModel, weak playbackRuntime] in
                        guard let appModel, let playbackRuntime else { return }
                        AppModel.recordProbe(
                            "formatRebuild begin"
                                + " lifecycle=\(playbackRuntime.productLifecycle)"
                                + " presentation=\(String(describing: playbackRuntime.attachedPresentation))"
                        )
                        do {
                            try await playbackRuntime
                                .rebuildTechnicalSessionForCurrentPresentation()
                            AppModel.recordProbe(
                                "formatRebuild ok"
                                    + " lifecycle=\(playbackRuntime.productLifecycle)"
                            )
                        } catch {
                            AppModel.recordProbe(
                                "formatRebuild failed"
                                    + " lifecycle=\(playbackRuntime.productLifecycle)"
                                    + " error=\(error)"
                            )
                            await playbackRuntime.stopAndWait()
                            appModel.requestStoppedPlaybackCleanup()
                            playbackRuntime.setUserVisibleIssue(.presentationConversionFailed)
                        }
                    }
                case .switchToPortal:
                    _ = try appModel.requestPlaybackPresentation(
                        .portal,
                        mediaSessionID: playbackRuntime.activeSessionID,
                        wasPlaying: playbackRuntime.productLifecycle == .playing
                    )
                case .returnToWindow:
                    _ = try appModel.requestPlaybackPresentation(
                        .window,
                        mediaSessionID: playbackRuntime.activeSessionID,
                        wasPlaying: playbackRuntime.productLifecycle == .playing
                    )
                }
            } catch {
                // The core format already succeeded. Report only the distinct
                // presentation failure and keep that effective interpretation.
                Self.logger.error(
                    "format presentation resolution failed error=\(error.localizedDescription, privacy: .public)"
                )
                playbackRuntime.setUserVisibleIssue(.presentationTransitionFailed)
            }
        }
        playbackVideoEntityStore.onRealityKitContentTypeChanged = nil
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
            onPlay: {
                AppModel.recordProbe("openRequestForwarded")
                launcher.requestPlayback($0.playbackLaunchRequest)
            }
        )
        let mediaLibrary = mediaLibraryFeature.library
        mediaLibrary.diagnosticProbe = { AppModel.recordProbe($0) }
        let browser = mediaLibraryFeature.browser

        launcher.nextFileProvider = {
            [weak embySession, weak mediaLibrary, weak browser, weak playbackRuntime] in
            switch playbackRuntime?.currentLaunchRequest?.collectionOrigin {
            case .mediaLibrary:
                return await mediaLibrary?.nextPlaybackItem()?.playbackLaunchRequest
            case .mediaServer:
                return await embySession?.nextPlaybackRequest()
            case .sourceDirectory:
                return await browser?.nextPlaybackItem()?.playbackLaunchRequest
            case .standalone, nil:
                return nil
            }
        }
        launcher.playbackQueueProvider = {
            [weak embySession, weak mediaLibrary, weak browser, weak playbackRuntime] in
            switch playbackRuntime?.currentLaunchRequest?.collectionOrigin {
            case .mediaLibrary:
                return mediaLibrary?.mediaCollectionSnapshot.playbackQueueSnapshot ?? .empty
            case .mediaServer:
                return embySession?.playbackQueue ?? .empty
            case .sourceDirectory:
                return browser?.mediaCollectionSnapshot.playbackQueueSnapshot ?? .empty
            case .standalone, nil:
                return .empty
            }
        }
        launcher.queueSelectionProvider = {
            [weak embySession, weak mediaLibrary, weak browser, weak playbackRuntime] id in
            switch playbackRuntime?.currentLaunchRequest?.collectionOrigin {
            case .mediaLibrary:
                return await mediaLibrary?.playbackItem(forCollectionItemID: id)?.playbackLaunchRequest
            case .mediaServer:
                return await embySession?.playbackRequest(forQueueID: id)
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
        ) ?? .defaultScenic
        appModel.configureDefaultEnvironment(configuredEnvironment)

        self.appModel = appModel
        self.playbackRuntime = playbackRuntime
        self.playbackVideoEntityStore = playbackVideoEntityStore
        embyNavigationModel = embyNavigation
        embySessionViewModel = embySession
        embyConnectionViewModel = embyConnection
        embyHomeViewModel = embyHome
        embySearchViewModel = embySearch
        let spatialPlatformEffectCoordinator = SpatialPlatformEffectCoordinator(
            appModel: appModel,
            playbackRuntime: playbackRuntime,
            playbackVideoEntityStore: playbackVideoEntityStore,
            stopPlaybackForFailedPresentationTransfer: { [weak launcher] in
                await launcher?.stopPlaybackAndWait()
            },
            persistSettledPlaybackMode: { [weak launcher] presentation in
                let mode: PersistedPlaybackMode = switch presentation {
                case .window, .docked: .window
                case .portal, .panorama: .panorama
                }
                launcher?.savePlaybackMode(mode)
            }
        )
        self.spatialPlatformEffectCoordinator = spatialPlatformEffectCoordinator
        playbackRuntime.setSessionLifecycleHandler { [weak spatialPlatformEffectCoordinator] event in
            spatialPlatformEffectCoordinator?.playbackSessionLifecycleChanged(event)
        }
        fileBrowsingViewModel = browser
        mediaLibraryViewModel = mediaLibrary
        mediaLibraryUIState = mediaLibraryFeature.uiState
        playbackLauncher = launcher
        settingsViewModel = SettingsViewModel(store: preferencesStore)
        self.certificateTrustPrompt = certificateTrustPrompt
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
        let playbackAddress: PlaybackAddress
        if let byteStreamHandle {
            playbackAddress = PlaybackAddress(byteStreamHandle: byteStreamHandle)
        } else {
            do {
                playbackAddress = try PlaybackAddress(localFileURL: url)
            } catch {
                preconditionFailure("A remote media item reached playback without a byte-stream handle.")
            }
        }
        return PlaybackLaunchRequest(
            source: playbackAddress,
            displayName: displayName,
            fileIdentifier: stableIdentifier.map(PlaybackFileIdentifier.init(rawValue:)),
            initialMetadata: PlaybackMediaMetadata(fileSizeInBytes: sizeInBytes),
            collectionOrigin: playbackOrigin,
            versionedIdentity: versionedIdentity,
            sourceAccess: accessLease,
            externalSubtitleSources: externalSubtitleSources,
            externalSubtitleResolutionFailed: externalSubtitleResolutionFailed
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
            .environment(application.playbackVideoEntityStore)
            .environment(application.spatialPlatformEffectCoordinator)
            .environment(application.embyNavigationModel)
            .environment(application.embySessionViewModel)
            .environment(application.embyConnectionViewModel)
            .environment(application.embyHomeViewModel)
            .environment(application.embySearchViewModel)
            .environment(application.fileBrowsingViewModel)
            .environment(application.mediaLibraryViewModel)
            .environment(application.mediaLibraryUIState)
            .environment(application.playbackLauncher)
            .environment(application.settingsViewModel)
            .environment(application.certificateTrustPrompt)
    }
}
