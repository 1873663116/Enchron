import PlaybackCore
@preconcurrency import Photos
import SwiftUI
import RealityKitScripting

@main
struct XrPlayerApp: App {
    @State private var appModel: AppModel
    @State private var playbackRuntime: PlaybackRuntime
    @State private var fileBrowsingViewModel: FileBrowsingViewModel
    @State private var mediaLibraryViewModel: MediaLibraryViewModel
    @State private var playbackLauncher: PlaybackLaunchCoordinator
    @State private var thumbnailService: ThumbnailService
    @State private var immersionStyle: ImmersionStyle = .full

    init() {
        do {
            try RKS.initialize()
        } catch {
            assertionFailure("RealityKitScripting initialization failed: \(error)")
        }

        let environment = ProcessInfo.processInfo.environment
        let isUITesting = environment["ENCHRON_UI_TESTING"] == "1"
        let defaults: UserDefaults
        if isUITesting {
            let suiteName = "app.enchron.ui-testing"
            defaults = UserDefaults(suiteName: suiteName) ?? .standard
            defaults.removePersistentDomain(forName: suiteName)
        } else {
            defaults = .standard
        }
        if environment["ENCHRON_RESET_MEDIA_LIBRARY"] == "1" {
            defaults.removeObject(forKey: "enchron.mediaLibrary")
        }
        let persistenceStore = SwiftDataStore(defaults: defaults)
        let preferencesStore = UserDefaultsStore(defaults: defaults)
        if isUITesting {
            preferencesStore.savePreferences(
                .init(resumePolicy: .alwaysStartFromBeginning)
            )
        }

        let appModel = AppModel(screenPositionStore: persistenceStore)
        let playbackRuntime = PlaybackRuntime(isUITestFixture: isUITesting)
        let metadataService = PlaybackMediaMetadataService()
        let prefetchService = MediaProfilePrefetchService(metadataService: metadataService)
        let launcher = PlaybackLaunchCoordinator(
            playbackRuntime: playbackRuntime,
            progressStore: persistenceStore,
            preferencesStore: preferencesStore,
            metadataService: metadataService,
            prefetchService: prefetchService
        )
        let mediaReferenceResolver = MediaReferenceResolver()
        let fixtureSourceID = UUID(uuidString: "00000000-0000-0000-0000-000000000101")!
        let mediaLibraryStore = UserDefaultsMediaLibraryStore(defaults: defaults)
        let mediaLibrary = MediaLibraryViewModel(
            store: mediaLibraryStore,
            resolver: mediaReferenceResolver,
            initialLibrary: isUITesting ? Self.makeUITestLibrary(sourceID: fixtureSourceID) : nil,
            onPlay: launcher.requestPlayback
        )
        let dataSource: any LocalFileSource = isUITesting
            ? FakeFileDataSource(catalog: .demo)
            : LocalDataSourceAdapter()
        let browser = FileBrowsingViewModel(
            localDataSource: dataSource,
            localDataSourceID: fixtureSourceID,
            prefetchService: prefetchService,
            onPlayFile: launcher.requestPlayback
        )

        mediaReferenceResolver.resolveSourceItem = { [weak browser] sourceID, path, reference in
            guard let browser else { throw MediaReferenceResolver.ResolutionError.unavailableSource }
            return try await browser.resolveSourceItem(
                dataSourceID: sourceID,
                path: path,
                reference: reference
            )
        }

        launcher.nextFileProvider = { [weak mediaLibrary, weak browser, weak playbackRuntime] in
            if let next = await mediaLibrary?.nextPlaybackRequest() {
                return next
            }
            guard let browser,
                  let request = playbackRuntime?.currentLaunchRequest,
                  let index = browser.files.firstIndex(where: { $0.name == request.displayName }),
                  browser.files.indices.contains(index + 1) else { return nil }
            return try? await browser.playbackRequest(for: browser.files[index + 1])
        }

        let preferences = preferencesStore.loadPreferences()
        appModel.controlsAutoHideSeconds = preferences.controlsAutoHideSeconds
        if let environment = SpatialSceneDomain.CinemaEnvironment(preferenceValue: preferences.defaultEnvironmentID) {
            appModel.currentCinemaEnvironment = environment
        }

        _appModel = State(initialValue: appModel)
        _playbackRuntime = State(initialValue: playbackRuntime)
        _fileBrowsingViewModel = State(initialValue: browser)
        _mediaLibraryViewModel = State(initialValue: mediaLibrary)
        _playbackLauncher = State(initialValue: launcher)
        _thumbnailService = State(initialValue: .shared)

        Task.detached(priority: .background) {
            await persistenceStore.cleanExpiredProgress(olderThan: 5)
        }

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
        guard let source = environment["ENCHRON_AUTOPLAY_FILE"], source.isEmpty == false else { return }
        Task { @MainActor in
            let url: URL
            if let parsedURL = URL(string: source), parsedURL.scheme?.isEmpty == false {
                url = parsedURL
            } else {
                url = URL(fileURLWithPath: source)
            }
            if isUITesting || !url.isFileURL {
                launcher.requestPlayback(PlaybackLaunchRequest(
                    url: url,
                    displayName: url.lastPathComponent
                ))
                return
            }
            mediaLibrary.addFiles([url])
            guard let reference = mediaLibrary.references.first(where: { $0.name == url.lastPathComponent }) else {
                mediaLibrary.lastErrorMessage = "The verification media could not be added to Media Library."
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
                mediaLibrary.lastErrorMessage = "Photos Full Access is required for automated playback verification."
                return
            }
            guard let asset = PHAsset.fetchAssets(with: .video, options: nil).firstObject else {
                mediaLibrary.lastErrorMessage = "No Photos video is available for automated playback verification."
                return
            }
            let name = PHAssetResource.assetResources(for: asset).first?.originalFilename
                ?? "Photos Video"
            mediaLibrary.addPhotoItems([(asset.localIdentifier, name)])
            guard let reference = mediaLibrary.references.last else {
                mediaLibrary.lastErrorMessage = "The Photos video reference could not be created."
                return
            }
            mediaLibrary.play(reference)
        }
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            MainView()
                .environment(appModel)
                .environment(playbackRuntime)
                .environment(fileBrowsingViewModel)
                .environment(mediaLibraryViewModel)
                .environment(playbackLauncher)
                .environment(thumbnailService)
        }
        .defaultSize(width: 1280, height: 720)
        .windowResizability(.contentSize)

        WindowGroup(id: "playerControls") {
            SpatialPlaybackControlsRoot()
                .environment(appModel)
                .environment(playbackRuntime)
                .environment(fileBrowsingViewModel)
                .environment(mediaLibraryViewModel)
                .environment(playbackLauncher)
                .environment(thumbnailService)
        }
        .defaultSize(width: 760, height: 220)
        .windowResizability(.contentSize)

        WindowGroup(id: AppModel.senseZoneVolumeID) {
            SenseZoneVolumeRoot()
                .environment(appModel)
        }
        .windowStyle(.volumetric)
        .defaultSize(width: 1.4, height: 0.9, depth: 0.8, in: .meters)

        ImmersiveSpace(id: appModel.immersiveSpaceID) {
            ImmersiveSpaceView()
                .environment(appModel)
                .environment(playbackRuntime)
                .onAppear {
                    appModel.immersiveSpaceState = .open
                    Task { await appModel.loadScreenPosition() }
                }
                .onDisappear {
                    if playbackRuntime.attachedPresentation != .window {
                        playbackRuntime.detach()
                    }
                    appModel.immersiveSpaceState = .closed
                    if let transition = appModel.presentationTransition,
                       transition.targetPresentation != .window {
                        appModel.rollbackPlaybackPresentation(transition.id)
                    }
                    appModel.isEnvironmentImmersiveActive = false
                }
        }
        .immersionStyle(selection: $immersionStyle, in: .mixed, .full)
        .onChange(of: appModel.isFullImmersion) { _, full in
            immersionStyle = full ? .full : .mixed
        }
    }

    private static func makeUITestLibrary(sourceID: UUID) -> FileBrowsingDomain.MediaLibrary {
        var library = FileBrowsingDomain.MediaLibrary()
        for name in ["Interstellar.mkv", "The Matrix.mkv", "Arrival.mkv"] {
            try? library.add(
                .init(
                    name: name,
                    locator: .sourceItem(dataSourceID: sourceID, path: "fake:///\(name)")
                )
            )
        }
        return library
    }
}
