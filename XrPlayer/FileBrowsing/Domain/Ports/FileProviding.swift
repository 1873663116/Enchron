import Foundation

public nonisolated protocol FileProviding {
    func listFiles(
        in folder: FileBrowsingDomain.MediaFolder,
        sortBy: FileBrowsingDomain.SortCriteria
    ) async throws -> [FileBrowsingDomain.MediaFile]

    func resolvePlayableURL(for file: FileBrowsingDomain.MediaFile) async throws -> URL
}
