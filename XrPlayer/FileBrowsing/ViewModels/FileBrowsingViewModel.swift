import Foundation
import Observation

@MainActor
@Observable
public final class FileBrowsingViewModel {
    public var files: [FileBrowsingDomain.MediaFile] = []
    public var isLoading: Bool = false

    private let localDataSource: LocalDataSourceAdapter
    private let onPlayFile: @MainActor (URL) -> Void
    private let rootURL: URL

    public init(
        localDataSource: LocalDataSourceAdapter,
        fileManager: FileManager = .default,
        onPlayFile: @escaping @MainActor (URL) -> Void
    ) {
        self.localDataSource = localDataSource
        self.onPlayFile = onPlayFile
        self.rootURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)

        Task { [weak self] in
            await self?.connectAndLoad()
        }
    }

    public func loadFiles() async {
        isLoading = true
        defer { isLoading = false }

        do {
            files = try await localDataSource.listContents(at: ".")
        } catch {
            files = []
        }
    }

    public func selectFile(_ file: FileBrowsingDomain.MediaFile) {
        Task { [weak self] in
            guard let self else { return }
            do {
                let playableURL = try await localDataSource.resolvePlayableURL(for: file)
                onPlayFile(playableURL)
            } catch {
                return
            }
        }
    }

    private func connectAndLoad() async {
        do {
            try await localDataSource.connect(
                with: .init(sourceType: .local, rootPath: rootURL.path)
            )
            await loadFiles()
        } catch {
            files = []
        }
    }
}
