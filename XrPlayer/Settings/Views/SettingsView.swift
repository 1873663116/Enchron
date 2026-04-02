import SwiftUI

public struct SettingsView: View {
    @Environment(AppModel.self) private var appModel
    @State private var resumePolicy: PersistenceDomain.ResumePolicy = .askEveryTime
    @State private var playbackEndBehavior: PersistenceDomain.PlaybackEndBehavior = .stop
    @State private var defaultPlaybackSpeed: Double = 1.0
    @State private var isCurvedScreen: Bool = false
    @State private var isFullImmersion: Bool = true
    @State private var selectedEnvironment: SpatialSceneDomain.CinemaEnvironment = .darkTheatre
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

                Picker("When Video Ends", selection: $playbackEndBehavior) {
                    Text("Stop").tag(PersistenceDomain.PlaybackEndBehavior.stop)
                    Text("Repeat").tag(PersistenceDomain.PlaybackEndBehavior.repeatOne)
                    Text("Play Next").tag(PersistenceDomain.PlaybackEndBehavior.playNext)
                }

                Picker("Default Speed", selection: $defaultPlaybackSpeed) {
                    ForEach(PlaybackCoreDomain.PlaybackSpeed.allCases, id: \.value) { speed in
                        Text(Self.speedLabel(speed.value)).tag(speed.value)
                    }
                }
            }

            Section("Immersive Space") {
                ToggleImmersiveSpaceButton()

                Picker("Immersion Style", selection: $isFullImmersion) {
                    Text("Full").tag(true)
                    Text("Mixed").tag(false)
                }

                Picker("Screen Shape", selection: $isCurvedScreen) {
                    Text("Flat").tag(false)
                    Text("Curved").tag(true)
                }

                Picker("Environment", selection: $selectedEnvironment) {
                    ForEach(SpatialSceneDomain.CinemaEnvironment.allCases, id: \.self) { env in
                        Text(env.displayName).tag(env)
                    }
                }
            }

            Section("About") {
                LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1")
                LabeledContent("Build", value: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—")
            }
        }
        .navigationTitle("Settings")
        .onAppear {
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
}
