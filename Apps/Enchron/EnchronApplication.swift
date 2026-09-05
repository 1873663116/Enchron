import Foundation
import DesignSystem
import Emby
import MediaLibrary
import MediaSource
import Observation
import OSLog
import Playback
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
final class ServerCertificateChangePlaybackBoundary {
    private let hasActivePlayback: () -> Bool
    private let isPlaybackPlaying: () -> Bool
    private let pausePlayback: () -> Void
    private let setUserVisibleIssue: (PlaybackUserVisibleIssue?) -> Void
    private let recordDiagnostic: (String) -> Void
    private var protectsCertificateChangeIssue = false

    init(
        hasActivePlayback: @escaping () -> Bool,
        isPlaybackPlaying: @escaping () -> Bool,
        pausePlayback: @escaping () -> Void,
        setUserVisibleIssue: @escaping (PlaybackUserVisibleIssue?) -> Void,
        recordDiagnostic: @escaping (String) -> Void
    ) {
        self.hasActivePlayback = hasActivePlayback
        self.isPlaybackPlaying = isPlaybackPlaying
        self.pausePlayback = pausePlayback
        self.setUserVisibleIssue = setUserVisibleIssue
        self.recordDiagnostic = recordDiagnostic
    }

    func receive(_ change: ServerCertificateChange) {
        protectsCertificateChangeIssue = hasActivePlayback()
        recordDiagnostic(
            "certificateBoundary changed previous=\(change.previousFingerprint)"
                + " new=\(change.currentFingerprint)"
        )
        if isPlaybackPlaying() {
            pausePlayback()
        }
        setUserVisibleIssue(.serverCertificateChanged)
    }

    func receive(_ observation: PlaybackRuntimeObservation) {
        switch observation.event {
        case .activeFailure where protectsCertificateChangeIssue:
            setUserVisibleIssue(.serverCertificateChanged)
        case .stopped:
            protectsCertificateChangeIssue = false
        case .diagnostics, .lifecycle, .activeFailure, .seekCompleted:
            break
        }
    }
}

@MainActor
@Observable
final class EnchronApplication {
    private static let logger = Logger(subsystem: "app.enchron", category: "Application")
    let appModel: AppModel
    let playbackSessionModel: PlaybackSessionModel
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
    let modalPresentationCoordinator: AppModalPresentationCoordinator
    let connectionSecurityPrompt: ConnectionSecurityPrompt
    private let certificateChangePlaybackBoundary: ServerCertificateChangePlaybackBoundary
    let spatialPlatformEffectCoordinator: SpatialPlatformEffectCoordinator
    #if DEBUG
        let playbackSwitchStateRing = PlaybackSwitchStateRing(capacity: 2_048)
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
           mediaStateSuiteName != preferencesSuiteName,
           let mediaStateDefaults = UserDefaults(suiteName: mediaStateSuiteName) {
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
        let playbackSessionModel = PlaybackSessionModel(
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
        let modalPresentationCoordinator = AppModalPresentationCoordinator()
        let connectionSecurityPrompt = ConnectionSecurityPrompt(
            modalPresentationCoordinator: modalPresentationCoordinator
        )
        ServerTrustPolicy.shared.approvalHandler = {
            [weak connectionSecurityPrompt, weak playbackRuntime] approval in
            let phase = playbackRuntime?.currentLaunchRequest == nil
                ? "connection"
                : "playback"
            let certificate = approval.certificate
            SurfaceInputProbes.record(
                "certificateBoundary promptRequested phase=\(phase)"
                    + " address=\(certificate.address)"
                    + " fingerprint=\(certificate.sha256Fingerprint)",
                retention: .evidence
            )
            return await connectionSecurityPrompt?
                .requestApproval(for: .unverifiedCertificate(approval)) ?? false
        }
        CleartextExposurePolicy.shared.approvalHandler = {
            [weak connectionSecurityPrompt] host in
            SurfaceInputProbes.record(
                "cleartextBoundary promptRequested host=\(host)",
                retention: .evidence
            )
            return await connectionSecurityPrompt?
                .requestApproval(for: .cleartextCredentials(host: host)) ?? false
        }
        let playbackVideoEntityStore = PlaybackVideoEntityStore()
        let launcher = PlaybackLaunchCoordinator(
            playbackRuntime: playbackRuntime,
            mediaStateSuiteName: mediaStateSuiteName,
            preferencesProvider: preferencesStore
        )
        let certificateChangePlaybackBoundary = ServerCertificateChangePlaybackBoundary(
            hasActivePlayback: { [weak playbackRuntime] in
                playbackRuntime?.currentLaunchRequest != nil
            },
            isPlaybackPlaying: { [weak playbackRuntime] in
                playbackRuntime?.productLifecycle == .playing
            },
            pausePlayback: { [weak playbackRuntime] in
                playbackRuntime?.pause()
            },
            setUserVisibleIssue: { [weak playbackRuntime] issue in
                playbackRuntime?.setUserVisibleIssue(issue)
            },
            recordDiagnostic: {
                SurfaceInputProbes.record($0, retention: .evidence)
            }
        )
        let launcherPlaybackObservationHandler = playbackRuntime.onPlaybackObservation
        playbackRuntime.onPlaybackObservation = {
            [weak certificateChangePlaybackBoundary] observation in
            launcherPlaybackObservationHandler?(observation)
            certificateChangePlaybackBoundary?.receive(observation)
        }
        ServerTrustPolicy.shared.certificateChangeHandler = {
            [weak certificateChangePlaybackBoundary] change in
            certificateChangePlaybackBoundary?.receive(change)
        }
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
            SurfaceInputProbes.record($0, retention: .evidence)
        }
#endif
        let embyConnection = EmbyConnectionViewModel(session: embySession)
        let embyHome = EmbyHomeViewModel(client: embyClient, session: embySession)
        let embySearch = EmbySearchViewModel(client: embyClient, session: embySession)
        launcher.onPlaybackModeEntryStarted = { [weak playbackSessionModel] mode, isColdLaunch in
            guard let playbackSessionModel else { return mode }
            playbackSessionModel.showControls = false
            guard isColdLaunch else {
                return switch playbackSessionModel.playbackPresentation {
                case .window, .docked: .window
                case .portal, .panorama: .panorama
                }
            }
            let family: PresentationContentFamily = switch mode {
            case .window: .flat
            case .panorama: .panoramic
            }
            playbackSessionModel.prepareColdPlaybackLaunch(for: family)
            return mode
        }
        launcher.onEffectiveMediaFormatApplied = {
            [weak playbackSessionModel, weak playbackRuntime] interpretation in
            guard let playbackSessionModel, let playbackRuntime else { return }
            let resolution = EffectiveMediaFormatPresentationResolver.resolve(
                interpretation,
                from: playbackSessionModel.playbackPresentation
            )
            do {
                switch resolution {
                case .unchanged:
                    guard playbackRuntime.technicalSessionFormatReplacementIsPending else {
                        return
                    }
                    Task { @MainActor [weak playbackSessionModel, weak playbackRuntime] in
                        guard let playbackSessionModel, let playbackRuntime else { return }
                        SurfaceInputProbes.record(
                            "formatRebuild begin"
                                + " lifecycle=\(playbackRuntime.productLifecycle)"
                                + " presentation=\(String(describing: playbackRuntime.attachedPresentation))"
                        )
                        do {
                            try await playbackRuntime
                                .rebuildTechnicalSessionForCurrentPresentation()
                            SurfaceInputProbes.record(
                                "formatRebuild ok"
                                    + " lifecycle=\(playbackRuntime.productLifecycle)"
                            )
                        } catch {
                            SurfaceInputProbes.record(
                                "formatRebuild failed"
                                    + " lifecycle=\(playbackRuntime.productLifecycle)"
                                    + " error=\(error)"
                            )
                            await playbackRuntime.stopAndWait()
                            playbackSessionModel.requestStoppedPlaybackCleanup()
                            playbackRuntime.setUserVisibleIssue(.presentationConversionFailed)
                        }
                    }
                case .switchToPortal:
                    _ = try playbackSessionModel.requestPlaybackPresentation(
                        .portal,
                        mediaSessionID: playbackRuntime.activeSessionID,
                        wasPlaying: playbackRuntime.productLifecycle == .playing
                    )
                case .returnToWindow:
                    _ = try playbackSessionModel.requestPlaybackPresentation(
                        .window,
                        mediaSessionID: playbackRuntime.activeSessionID,
                        wasPlaying: playbackRuntime.productLifecycle == .playing
                    )
                }
            } catch {
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
            durationProbe: Self.durationProbe(launcher),
            onPlay: {
                SurfaceInputProbes.record("openRequestForwarded")
                launcher.requestPlayback($0.playbackLaunchRequest)
            }
        )
        let mediaLibrary = mediaLibraryFeature.library
        mediaLibrary.diagnosticProbe = { SurfaceInputProbes.record($0) }
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
        launcher.onPlaybackStopRequested = { [weak mediaLibrary, weak browser] in
            mediaLibrary?.refreshViewingStates()
            browser?.refreshViewingStates()
        }

        let preferences = preferencesStore.loadPreferences()
        if let override = environment["ENCHRON_CONTROLS_AUTO_HIDE_SECONDS"].flatMap(Int.init),
           override > 0 {
            playbackSessionModel.controlsAutoHideSeconds = override
        } else {
            playbackSessionModel.controlsAutoHideSeconds = preferences.controlsAutoHideSeconds
        }
        let configuredEnvironment = SpatialSceneDomain.CinemaEnvironment(
            preferenceValue: preferences.defaultEnvironmentID
        ) ?? .defaultScenic
        playbackSessionModel.configureDefaultEnvironment(configuredEnvironment)

        appModel = AppModel()
        self.playbackSessionModel = playbackSessionModel
        self.playbackRuntime = playbackRuntime
        self.playbackVideoEntityStore = playbackVideoEntityStore
        embyNavigationModel = embyNavigation
        embySessionViewModel = embySession
        embyConnectionViewModel = embyConnection
        embyHomeViewModel = embyHome
        embySearchViewModel = embySearch
        let spatialPlatformEffectCoordinator = SpatialPlatformEffectCoordinator(
            session: playbackSessionModel,
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
        let settings = SettingsViewModel(store: preferencesStore)
        settings.onArtworkCacheCleared = { [weak mediaLibrary, weak browser] in
            mediaLibrary?.forgetArtwork()
            browser?.refreshViewingStates()
        }
        settingsViewModel = settings
        self.connectionSecurityPrompt = connectionSecurityPrompt
        self.certificateChangePlaybackBoundary = certificateChangePlaybackBoundary
        self.modalPresentationCoordinator = modalPresentationCoordinator
        #if DEBUG
            playbackSessionModel.playbackSwitchPresentationRequestHandler = { [weak playbackSwitchStateRing, weak playbackRuntime] _, target in
                playbackRuntime?.debugCapturePlaybackSwitchRendererState()
                _ = playbackSwitchStateRing?.beginSwitch(
                    kind: .presentation,
                    targetPresentation: target,
                    at: DispatchTime.now().uptimeNanoseconds
                )
            }
            playbackSessionModel.playbackSwitchPresentationSettlementHandler = { [weak playbackSwitchStateRing] presentation in
                playbackSwitchStateRing?.settlePresentation(presentation)
            }
            playbackRuntime.debugSetPlaybackFormatSwitchHandler { [weak playbackSwitchStateRing, weak playbackSessionModel, weak playbackRuntime] in
                playbackRuntime?.debugCapturePlaybackSwitchRendererState()
                _ = playbackSwitchStateRing?.beginSwitch(
                    kind: .format,
                    targetPresentation: playbackSessionModel?.playbackPresentation,
                    at: DispatchTime.now().uptimeNanoseconds
                )
            }
        #endif
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

    private static func durationProbe(
        _ launcher: PlaybackLaunchCoordinator
    ) -> MediaDurationProbe {
        { source, identity in
            guard let information = try? await MediaSourceProbe.information(for: source.url),
                  information.durationSeconds > 0 else { return nil }
            await launcher.recordKnownDuration(information.durationSeconds, for: identity)
            return information.durationSeconds
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
                if let duration = await launcher.knownDuration(for: identity) {
                    VideoCardViewingState(
                        positionSeconds: 0,
                        durationSeconds: duration,
                        isCompleted: false
                    )
                } else {
                    nil
                }
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

extension EnchronApplication {
    convenience init() {
        let environment = ProcessInfo.processInfo.environment
        self.init(environment: environment)
        #if DEBUG
            installTestCommandChannelIfEnabled(environment: environment)
        #endif
    }
}

extension View {
    func enchronEnvironment(_ application: EnchronApplication) -> some View {
        environment(application.appModel)
            .environment(application.playbackSessionModel)
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
            .environment(application.modalPresentationCoordinator)
            .environment(application.connectionSecurityPrompt)
    }
}
