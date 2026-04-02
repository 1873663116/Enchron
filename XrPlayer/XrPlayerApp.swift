import SwiftUI

@main
struct XrPlayerApp: App {
    private struct SmokeLaunchConfiguration {
        enum Panel: String {
            case tracks
            case timeline
        }

        let videoName: String
        let panel: Panel?
        let enableFirstSubtitle: Bool
        let hideControlsAfterSetup: Bool

        init?(environment: [String: String]) {
            guard environment["XRPLAYER_SMOKE_TEST"] == "1" else {
                return nil
            }

            self.videoName = environment["XRPLAYER_SMOKE_VIDEO"] ?? "sim-sample.mp4"
            self.panel = environment["XRPLAYER_SMOKE_PANEL"].flatMap(Panel.init(rawValue:))
            self.enableFirstSubtitle = environment["XRPLAYER_SMOKE_ENABLE_SUBTITLE"] == "1"
            self.hideControlsAfterSetup = environment["XRPLAYER_SMOKE_HIDE_CONTROLS"] == "1"
        }
    }

    @State private var appModel: AppModel
    @State private var windowVideoViewModel: WindowVideoViewModel
    @State private var fileBrowsingViewModel: FileBrowsingViewModel
    @State private var playbackLauncher: PlaybackLaunchCoordinator
    @State private var panoramaBridge: PanoramaLayerBridge

    init() {
        Task.detached(priority: .utility) {
            Self.copySampleVideoIfAvailable()
        }

        let appModel = AppModel()
        let savedPrefs = UserDefaultsStore().loadPreferences()
        if savedPrefs.isScreenCurved {
            appModel.screenShape = .curved(radius: 3.0, height: 1.35)
        }
        let player = MPVPlayerAdapter()
        let windowVideoViewModel = WindowVideoViewModel(player: player)
        let smokeLaunch = SmokeLaunchConfiguration(environment: ProcessInfo.processInfo.environment)

        let launcher = PlaybackLaunchCoordinator(
            appModel: appModel,
            windowVideoViewModel: windowVideoViewModel
        )

        // Clean up expired playback progress entries (older than 5 days).
        Task.detached(priority: .background) {
            await SwiftDataStore().cleanExpiredProgress(olderThan: 5)
        }

        // Clean up Photo Library temp exports older than 5 days.
        Task.detached(priority: .background) {
            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("xrplayer-photos", isDirectory: true)
            guard let files = try? FileManager.default.contentsOfDirectory(
                at: tempDir, includingPropertiesForKeys: [.contentModificationDateKey]
            ) else { return }
            let cutoff = Date().addingTimeInterval(-5 * 24 * 3600)
            for file in files {
                if let attrs = try? file.resourceValues(forKeys: [.contentModificationDateKey]),
                   let modified = attrs.contentModificationDate,
                   modified < cutoff {
                    try? FileManager.default.removeItem(at: file)
                }
            }
        }

        // Pre-warm MPV in the background to reduce first-play black-screen latency.
        player.warmup()
        let localDataSource = LocalDataSourceAdapter()
        let fileBrowsingViewModel = FileBrowsingViewModel(
            localDataSource: localDataSource,
            onPlayFile: { request in
                launcher.beginPlayback(request)
            },
            onPrepareFile: { request in
                launcher.preparePlayback(request)
            }
        )

        // Wire auto-next-episode: find the next file after the current one in the sorted file list
        launcher.nextFileProvider = { [weak fileBrowsingViewModel, weak windowVideoViewModel] in
            guard let vm = fileBrowsingViewModel,
                  let currentRequest = windowVideoViewModel?.currentLaunchRequest else { return nil }

            guard let currentIndex = vm.files.firstIndex(where: {
                $0.name == currentRequest.displayName
            }) else { return nil }

            let nextIndex = currentIndex + 1
            guard nextIndex < vm.files.count else { return nil }

            return try? await vm.playbackRequest(for: vm.files[nextIndex])
        }

        _appModel = State(initialValue: appModel)
        _windowVideoViewModel = State(initialValue: windowVideoViewModel)
        _fileBrowsingViewModel = State(initialValue: fileBrowsingViewModel)
        _playbackLauncher = State(initialValue: launcher)
        _panoramaBridge = State(initialValue: PanoramaLayerBridge())

        if let smokeLaunch {
            appModel.showControls = true
            Task { @MainActor in
                await Self.runSmokeLaunch(
                    smokeLaunch,
                    appModel: appModel,
                    windowVideoViewModel: windowVideoViewModel,
                    launcher: launcher
                )
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            MainView()
                .environment(appModel)
                .environment(windowVideoViewModel)
                .environment(fileBrowsingViewModel)
                .environment(playbackLauncher)
                .environment(panoramaBridge)
        }

        ImmersiveSpace(id: appModel.immersiveSpaceID) {
            ImmersiveSpaceView()
                .environment(appModel)
                .environment(panoramaBridge)
                .onAppear {
                    appModel.immersiveSpaceState = .open
                    Task {
                        await appModel.loadScreenPosition()
                    }
                }
                .onDisappear {
                    appModel.immersiveSpaceState = .closed
                    // Ensure bridge stops when immersive space is dismissed.
                    panoramaBridge.attachVideoLayer(nil)
                    if appModel.playbackMode != .window {
                        appModel.updatePlaybackMode(.window)
                    }
                }
        }
        .immersionStyle(selection: .constant(.full), in: .full)
    }

    nonisolated private static func copySampleVideoIfAvailable(fileManager: FileManager = .default) {
        guard let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return
        }

        let candidateNames = ["SampleMovie", "Sample Movie"]
        let candidateExtensions = ["mp4", "mov", "m4v", "mkv"]

        for name in candidateNames {
            for ext in candidateExtensions {
                guard let bundledURL = Bundle.main.url(forResource: name, withExtension: ext) else {
                    continue
                }

                // Avoid blocking startup by copying very large bundled media.
                if let size = try? bundledURL.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                   size > 200 * 1024 * 1024 {
                    continue
                }

                let destinationURL = documentsURL.appendingPathComponent("\(name).\(ext)")
                guard !fileManager.fileExists(atPath: destinationURL.path) else { return }

                do {
                    try fileManager.copyItem(at: bundledURL, to: destinationURL)
                } catch {
                    return
                }
                return
            }
        }
    }

    @MainActor
    private static func runSmokeLaunch(
        _ configuration: SmokeLaunchConfiguration,
        appModel: AppModel,
        windowVideoViewModel: WindowVideoViewModel,
        launcher: PlaybackLaunchCoordinator
    ) async {
        guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return
        }

        let videoURL = documentsURL.appendingPathComponent(configuration.videoName)
        for _ in 0..<20 where FileManager.default.fileExists(atPath: videoURL.path) == false {
            try? await Task.sleep(for: .milliseconds(250))
        }

        guard FileManager.default.fileExists(atPath: videoURL.path) else {
            print("[SmokeTest] video not found at \(videoURL.path)")
            return
        }

        if let panel = configuration.panel {
            appModel.smokePanelRequest = panel.rawValue
        }

        print(
            "[SmokeTest] autoplay \(videoURL.lastPathComponent) panel=\(configuration.panel?.rawValue ?? "none") subtitle=\(configuration.enableFirstSubtitle)"
        )
        launcher.beginPlayback(for: videoURL)

        guard configuration.enableFirstSubtitle else {
            return
        }

        for _ in 0..<24 {
            if let track = windowVideoViewModel.availableSubtitleTracks.first {
                print("[SmokeTest] enabling subtitle track \(track.id) \(track.displayName)")
                windowVideoViewModel.selectSubtitleTrack(track)
                try? await Task.sleep(for: .milliseconds(700))
                if let state = windowVideoViewModel.debugSubtitleState() {
                    print("[SmokeTest] subtitle-state \(state)")
                }
                let screenshotURL = documentsURL.appendingPathComponent("smoke-subtitle-capture.png")
                windowVideoViewModel.captureScreenshot(to: screenshotURL)
                print("[SmokeTest] requested screenshot \(screenshotURL.lastPathComponent)")
                if configuration.hideControlsAfterSetup {
                    appModel.showControls = false
                    print("[SmokeTest] controls hidden")
                }
                break
            }
            try? await Task.sleep(for: .milliseconds(250))
        }
    }
}
