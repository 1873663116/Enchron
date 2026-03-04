import SwiftUI

@main
struct XrPlayerApp: App {
    @State private var appModel: AppModel
    @State private var windowVideoViewModel: WindowVideoViewModel
    @State private var fileBrowsingViewModel: FileBrowsingViewModel

    init() {
        Self.copySampleVideoIfAvailable()

        let appModel = AppModel()
        let player = MPVPlayerAdapter()
        let windowVideoViewModel = WindowVideoViewModel(player: player)
        let localDataSource = LocalDataSourceAdapter()
        let fileBrowsingViewModel = FileBrowsingViewModel(localDataSource: localDataSource) { url in
            appModel.startPlayback(url: url)
            Task {
                await windowVideoViewModel.play(url: url)
            }
        }

        _appModel = State(initialValue: appModel)
        _windowVideoViewModel = State(initialValue: windowVideoViewModel)
        _fileBrowsingViewModel = State(initialValue: fileBrowsingViewModel)
    }
    
    var body: some Scene {
        WindowGroup {
            MainView()
                .environment(appModel)
                .environment(windowVideoViewModel)
                .environment(fileBrowsingViewModel)
        }
        
        ImmersiveSpace(id: appModel.immersiveSpaceID) {
            ImmersiveSpaceView()
                .environment(appModel)
                .onAppear {
                    appModel.immersiveSpaceState = .open
                }
                .onDisappear {
                    appModel.immersiveSpaceState = .closed
                }
        }
        .immersionStyle(selection: .constant(.full), in: .full)
    }

    private static func copySampleVideoIfAvailable(fileManager: FileManager = .default) {
        guard let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return
        }

        let candidateNames = ["SampleMovie", "Sample Movie"]
        let candidateExtensions = ["mp4", "mov", "m4v"]

        for name in candidateNames {
            for ext in candidateExtensions {
                guard let bundledURL = Bundle.main.url(forResource: name, withExtension: ext) else {
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
}
