import SwiftUI

@main
struct XrPlayerApp: App {
    @State private var appModel: AppModel
    @State private var windowVideoViewModel: WindowVideoViewModel
    @State private var fileBrowsingViewModel: FileBrowsingViewModel

    init() {
        Task.detached(priority: .utility) {
            Self.copySampleVideoIfAvailable()
        }

        let appModel = AppModel()
        let player = MPVPlayerAdapter()
        let windowVideoViewModel = WindowVideoViewModel(player: player)
        let localDataSource = LocalDataSourceAdapter()
        let fileBrowsingViewModel = FileBrowsingViewModel(localDataSource: localDataSource) { url in
            appModel.startPlayback(url: url)
            Task {
                do {
                    try await windowVideoViewModel.play(url: url)
                } catch {
                    appModel.stopPlayback()
                }
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
}
