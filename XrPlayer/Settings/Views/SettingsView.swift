import SwiftUI

public struct SettingsView: View {
    @Environment(AppModel.self) private var appModel
    @State private var resumePolicy: PersistenceDomain.ResumePolicy = .askEveryTime
    @State private var playbackEndBehavior: PersistenceDomain.PlaybackEndBehavior = .stop
    @State private var defaultPlaybackSpeed: Double = 1.0
    @State private var isCurvedScreen: Bool = false
    @State private var isFullImmersion: Bool = true
    @State private var selectedEnvironment: SpatialSceneDomain.CinemaEnvironment = .darkTheatre
    @State private var cacheSizeBytes: Int64 = 0
    @State private var showClearCacheAlert = false
    @State private var cacheCleared = false
    private let preferencesStore: PreferencesStoring

    public init(preferencesStore: PreferencesStoring = UserDefaultsStore()) {
        self.preferencesStore = preferencesStore
    }

    public var body: some View {
        List {
            Section("Playback") {
                Picker("Resume Behavior", selection: $resumePolicy) {
                    Text("Ask Every Time").tag(PersistenceDomain.ResumePolicy.askEveryTime)
                    Text("Always Resume").tag(PersistenceDomain.ResumePolicy.alwaysResume)
                    Text("Always Start Over").tag(PersistenceDomain.ResumePolicy.alwaysStartFromBeginning)
                }
                .accessibilityIdentifier("Settings-Playback-picker-resumePolicy")

                Picker("When Video Ends", selection: $playbackEndBehavior) {
                    Text("Stop").tag(PersistenceDomain.PlaybackEndBehavior.stop)
                    Text("Repeat").tag(PersistenceDomain.PlaybackEndBehavior.repeatOne)
                    Text("Play Next").tag(PersistenceDomain.PlaybackEndBehavior.playNext)
                }
                .accessibilityIdentifier("Settings-Playback-picker-endBehavior")

                Picker("Default Speed", selection: $defaultPlaybackSpeed) {
                    ForEach(PlaybackCoreDomain.PlaybackSpeed.allCases, id: \.value) { speed in
                        Text(Self.speedLabel(speed.value)).tag(speed.value)
                    }
                }
                .accessibilityIdentifier("Settings-Playback-picker-defaultSpeed")
            }

            Section("Immersive Space") {
                ToggleImmersiveSpaceButton()

                Picker("Immersion Style", selection: $isFullImmersion) {
                    Text("Full").tag(true)
                    Text("Mixed").tag(false)
                }
                .accessibilityIdentifier("Settings-ImmersiveSpace-picker-immersionStyle")

                Picker("Screen Shape", selection: $isCurvedScreen) {
                    Text("Flat").tag(false)
                    Text("Curved").tag(true)
                }
                .accessibilityIdentifier("Settings-ImmersiveSpace-picker-screenShape")

                Picker("Environment", selection: $selectedEnvironment) {
                    ForEach(SpatialSceneDomain.CinemaEnvironment.allCases, id: \.self) { env in
                        Text(env.displayName).tag(env)
                    }
                }
                .accessibilityIdentifier("Settings-ImmersiveSpace-picker-environment")
            }

            Section("Storage") {
                LabeledContent("Cache Size", value: Self.formatBytes(cacheSizeBytes))
                    .accessibilityLabel("Cache size, \(Self.formatBytes(cacheSizeBytes))")
                    .accessibilityIdentifier("Settings-Storage-label-cacheSize")

                Button {
                    showClearCacheAlert = true
                } label: {
                    if cacheCleared {
                        Label("Cache Cleared", systemImage: "checkmark.circle")
                            .foregroundStyle(.green)
                    } else {
                        Label("Clear Cache", systemImage: "trash")
                            .foregroundStyle(.red)
                    }
                }
                .accessibilityLabel("Clear application cache")
                .accessibilityIdentifier("Settings-Storage-button-clearCache")
                .disabled(cacheSizeBytes == 0)
            }

            Section("About") {
                LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1")
                LabeledContent("Build", value: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—")
            }
        }
        .contentMargins(.top, 20, for: .scrollContent)
        .navigationTitle("Settings")
        .alert("Clear Cache", isPresented: $showClearCacheAlert) {
            Button("Clear", role: .destructive) {
                Task.detached(priority: .utility) {
                    Self.clearAppCache()
                    let newSize = Self.appCacheSizeBytes()
                    await MainActor.run {
                        cacheSizeBytes = newSize
                        cacheCleared = true
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will delete all cached data (\(Self.formatBytes(cacheSizeBytes))). Downloaded content will need to be reloaded.")
        }
        .onAppear {
            Task.detached(priority: .utility) {
                let size = Self.appCacheSizeBytes()
                await MainActor.run { cacheSizeBytes = size }
            }
            cacheCleared = false
            let prefs = preferencesStore.loadPreferences()
            resumePolicy = prefs.resumePolicy
            playbackEndBehavior = prefs.playbackEndBehavior
            defaultPlaybackSpeed = prefs.defaultPlaybackSpeed
            isCurvedScreen = prefs.isScreenCurved
            isFullImmersion = appModel.isFullImmersion
            selectedEnvironment = appModel.currentCinemaEnvironment
        }
        .onChange(of: resumePolicy) { _, newValue in
            var prefs = preferencesStore.loadPreferences()
            prefs.resumePolicy = newValue
            preferencesStore.savePreferences(prefs)
        }
        .onChange(of: playbackEndBehavior) { _, newValue in
            var prefs = preferencesStore.loadPreferences()
            prefs.playbackEndBehavior = newValue
            preferencesStore.savePreferences(prefs)
        }
        .onChange(of: defaultPlaybackSpeed) { _, newValue in
            var prefs = preferencesStore.loadPreferences()
            prefs.defaultPlaybackSpeed = newValue
            preferencesStore.savePreferences(prefs)
        }
        .onChange(of: isFullImmersion) { _, full in
            appModel.isFullImmersion = full
        }
        .onChange(of: isCurvedScreen) { _, curved in
            if curved {
                appModel.screenShape = .curved(radius: 3.0, height: 1.35)
            } else {
                appModel.screenShape = .flat(width: 2.4, height: 1.35)
            }
            var prefs = preferencesStore.loadPreferences()
            prefs.isScreenCurved = curved
            preferencesStore.savePreferences(prefs)
        }
        .onChange(of: selectedEnvironment) { _, newEnv in
            Task {
                await appModel.switchEnvironment(to: newEnv)
            }
        }
    }

    private static func speedLabel(_ value: Double) -> String {
        if value == Double(Int(value)) {
            return "\(Int(value)).0x"
        }
        return "\(value)x"
    }

    private static func appCacheSizeBytes() -> Int64 {
        guard let cacheURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return 0
        }
        return directorySize(at: cacheURL)
    }

    private static func directorySize(at url: URL) -> Int64 {
        var total: Int64 = 0
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        for case let fileURL as URL in enumerator {
            total += (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize.map(Int64.init)) ?? 0
        }
        return total
    }

    private static func clearAppCache() {
        guard let cacheURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return
        }
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: cacheURL, includingPropertiesForKeys: nil
        ) else { return }
        for url in contents {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private static func formatBytes(_ bytes: Int64) -> String {
        if bytes == 0 { return "Empty" }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
