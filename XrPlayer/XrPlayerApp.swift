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
        let runHDRProbe: Bool
        let runFullFrameHDRProbe: Bool

        init?(environment: [String: String]) {
            guard environment["XRPLAYER_SMOKE_TEST"] == "1" else {
                return nil
            }

            self.videoName = environment["XRPLAYER_SMOKE_VIDEO"] ?? "sim-sample.mp4"
            self.panel = environment["XRPLAYER_SMOKE_PANEL"].flatMap(Panel.init(rawValue:))
            self.enableFirstSubtitle = environment["XRPLAYER_SMOKE_ENABLE_SUBTITLE"] == "1"
            self.hideControlsAfterSetup = environment["XRPLAYER_SMOKE_HIDE_CONTROLS"] == "1"
            self.runHDRProbe = environment["XRPLAYER_SMOKE_HDR_PROBE"] == "1"
            self.runFullFrameHDRProbe = environment["XRPLAYER_SMOKE_HDR_FULL_FRAME"] == "1"
        }
    }

    @State private var appModel: AppModel
    @State private var windowVideoViewModel: WindowVideoViewModel
    @State private var fileBrowsingViewModel: FileBrowsingViewModel
    @State private var playbackLauncher: PlaybackLaunchCoordinator
    @State private var panoramaBridge: PanoramaLayerBridge
    @State private var thumbnailService: ThumbnailService
    @State private var immersionStyle: ImmersionStyle = .full

    init() {
        Task.detached(priority: .utility) {
            Self.copySampleVideoIfAvailable()
        }

        let appModel = AppModel()
        let savedPrefs = UserDefaultsStore().loadPreferences()
        if savedPrefs.isScreenCurved {
            appModel.screenShape = .curved(radius: 3.0, height: 1.35)
        }
        // FakeApp playback backend: an in-memory fake that simulates the playback
        // timeline (position / state / tracks) without decoding real media, so the
        // whole play loop runs on the fake catalog's fake:// URLs. Swap
        // FakePlaybackSource() → MPVPlayerAdapter() (and restore warmup below) to ship.
        let player = FakePlaybackSource()
        let windowVideoViewModel = WindowVideoViewModel(player: player)
        let smokeLaunch = SmokeLaunchConfiguration(environment: ProcessInfo.processInfo.environment)

        // §5.6: Shared metadata service — used by both the prefetch service and the
        // launcher so cache writes from background prefetch are immediately visible
        // to preparePlayback without a shared-state race.
        let sharedMetadataService = PlaybackMediaMetadataService()

        // §5.6: Single shared prefetch service — the launcher awaits in-flight
        // prefetch tasks started by FileBrowsingViewModel, eliminating race conditions.
        let sharedPrefetchService = MediaProfilePrefetchService(metadataService: sharedMetadataService)
        let launcher = PlaybackLaunchCoordinator(
            appModel: appModel,
            windowVideoViewModel: windowVideoViewModel,
            metadataService: sharedMetadataService,
            prefetchService: sharedPrefetchService
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

        // (mpv warmup is restored when swapping the player back to MPVPlayerAdapter.)
        // FakeApp data backend: the browsing UI runs on a deterministic
        // in-memory catalog (nine demo films + a folder hierarchy) so the whole
        // app is exercisable without real disk/network. Swap FakeFileDataSource()
        // → LocalDataSourceAdapter() at this single site to ship on real files.
        let localDataSource: any LocalFileSource = FakeFileDataSource()
        // FILE-01: tapping a video card plays it directly — no detail page. The
        // prepare/confirm path (which fed the retired VideoDetailView) is dropped, so
        // `selectFile` routes straight to `beginPlayback`.
        let fileBrowsingViewModel = FileBrowsingViewModel(
            localDataSource: localDataSource,
            prefetchService: sharedPrefetchService,
            onPlayFile: { request in
                launcher.beginPlayback(request)
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
        _thumbnailService = State(initialValue: ThumbnailService.shared)

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
        WindowGroup(id: "main") {
            MainView()
                .environment(appModel)
                .environment(windowVideoViewModel)
                .environment(fileBrowsingViewModel)
                .environment(playbackLauncher)
                .environment(panoramaBridge)
                .environment(thumbnailService)
        }
        .defaultSize(width: 1280, height: 720)
        .windowResizability(.contentSize)

        WindowGroup(id: "settings") {
            NavigationStack {
                SettingsView()
            }
            .environment(appModel)
        }

        WindowGroup(id: "playerControls") {
            PlayerControlsView()
                .environment(appModel)
                .environment(windowVideoViewModel)
                .environment(fileBrowsingViewModel)
                .environment(playbackLauncher)
                .environment(thumbnailService)
        }
        .defaultSize(width: 600, height: 200)

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
        .immersionStyle(selection: $immersionStyle, in: .mixed, .full)
        .onChange(of: appModel.isFullImmersion) { _, full in
            immersionStyle = full ? .full : .mixed
        }
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
        appendSmokeLog("autoplay video=\(videoURL.lastPathComponent)")
        launcher.beginPlayback(for: videoURL)

        if configuration.runHDRProbe {
            await runSmokeHDRProbe(
                configuration,
                windowVideoViewModel: windowVideoViewModel
            )
        }

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

    @MainActor
    private static func runSmokeHDRProbe(
        _ configuration: SmokeLaunchConfiguration,
        windowVideoViewModel: WindowVideoViewModel
    ) async {
        for attempt in 1...12 {
            try? await Task.sleep(for: .milliseconds(500))
            appendSmokeLog("sample=on_attempt_\(attempt) start")
            await windowVideoViewModel.sampleCurrentHDRDrawable(trigger: "smoke_probe_on_attempt_\(attempt)")
            if let sample = windowVideoViewModel.latestHDRProbeSample, sample.source == .mpvDrawable {
                print("[SmokeTest] hdr-probe-on-ready attempt=\(attempt)")
                appendSmokeProbeLog("on_attempt_\(attempt)", sample: sample)
                break
            } else if let error = windowVideoViewModel.lastHDRProbeError {
                appendSmokeLog("sample=on_attempt_\(attempt) failed error=\(error)")
                if error.contains("disabled on Simulator") {
                    break
                }
            }
        }

        if configuration.runFullFrameHDRProbe {
            await windowVideoViewModel.sampleFullFrameHDRDrawable()
            if let sample = windowVideoViewModel.latestHDRProbeSample {
                appendSmokeProbeLog("full_frame", sample: sample)
            }
        }

        windowVideoViewModel.setHDREnabled(false)
        try? await Task.sleep(for: .milliseconds(700))
        await windowVideoViewModel.sampleCurrentHDRDrawable(trigger: "smoke_probe_off")
        if let sample = windowVideoViewModel.latestHDRProbeSample {
            appendSmokeProbeLog("off", sample: sample)
        } else if let error = windowVideoViewModel.lastHDRProbeError {
            appendSmokeLog("sample=off failed error=\(error)")
        }

        windowVideoViewModel.setHDREnabled(true)
        try? await Task.sleep(for: .milliseconds(700))
        await windowVideoViewModel.sampleCurrentHDRDrawable(trigger: "smoke_probe_on_after_toggle")
        if let sample = windowVideoViewModel.latestHDRProbeSample {
            appendSmokeProbeLog("on_after_toggle", sample: sample)
        } else if let error = windowVideoViewModel.lastHDRProbeError {
            appendSmokeLog("sample=on_after_toggle failed error=\(error)")
        }

        if let delta = windowVideoViewModel.hdrProbeDelta {
            print(
                "[SmokeTest] hdr-probe-delta matched=true maxDelta=\(delta.maxRGBDelta) p99Delta=\(delta.p99LuminanceDelta) above1Delta=\(delta.countAbove1Delta) above2Delta=\(delta.countAbove2Delta)"
            )
            appendSmokeLog(
                "delta matched=true maxDelta=\(delta.maxRGBDelta) p99Delta=\(delta.p99LuminanceDelta) above1Delta=\(delta.countAbove1Delta) above2Delta=\(delta.countAbove2Delta)"
            )
        } else {
            print("[SmokeTest] hdr-probe-delta matched=false status=\(windowVideoViewModel.hdrProbeDeltaStatus)")
            appendSmokeLog("delta matched=false status=\(windowVideoViewModel.hdrProbeDeltaStatus)")
        }
    }

    private static func appendSmokeProbeLog(
        _ label: String,
        sample: PlaybackCoreDomain.HDRProbeSample
    ) {
        appendSmokeLog(
            [
                "sample=\(label)",
                "hdr=\(sample.hdrOutputEnabled.map(String.init) ?? "unknown")",
                "source=\(sample.source.rawValue)",
                "region=\(sample.probeRegion)",
                "format=\(sample.pixelFormat)",
                "colorspace=\(sample.colorspace)",
                "contract=\(sample.contract)",
                "size=\(sample.width)x\(sample.height)",
                "max=\(sample.statistics.maxRGB.maxChannel)",
                "p99=\(sample.statistics.p99Luminance)",
                "above1=\(sample.statistics.countAbove1)",
                "above2=\(sample.statistics.countAbove2)",
                "pixels=\(sample.statistics.sampledPixelCount)"
            ].joined(separator: " ")
        )
    }

    private static func appendSmokeLog(_ line: String) {
        guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return
        }
        let url = documentsURL.appendingPathComponent("hdr-probe-smoke.log")
        let payload = "\(Date().timeIntervalSince1970) \(line)\n"
        guard let data = payload.data(using: .utf8) else { return }
        if FileManager.default.fileExists(atPath: url.path),
           let handle = try? FileHandle(forWritingTo: url) {
            try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
            try? handle.close()
        } else {
            try? data.write(to: url)
        }
    }
}
