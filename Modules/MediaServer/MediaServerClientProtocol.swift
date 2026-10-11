import Foundation

public protocol MediaServerClientProtocol: Sendable {
    var kind: MediaServerKind { get }
    var capabilities: MediaServerCapabilities { get }
    func authenticate(_ login: MediaServerLogin) async throws -> MediaServerAuthenticatedServer

    func views(on server: MediaServerAuthenticatedServer) async throws -> [MediaServerLibraryView]

    func items(
        in viewID: MediaServerItemID,
        on server: MediaServerAuthenticatedServer,
        query: MediaServerItemQuery
    ) async throws -> MediaServerItemPage

    func item(
        withID itemID: MediaServerItemID,
        on server: MediaServerAuthenticatedServer
    ) async throws -> MediaServerLibraryItem

    func children(
        of parent: MediaServerLibraryItem,
        on server: MediaServerAuthenticatedServer,
        query: MediaServerItemQuery
    ) async throws -> MediaServerItemPage

    func resumeItems(
        on server: MediaServerAuthenticatedServer,
        query: MediaServerItemQuery
    ) async throws -> MediaServerItemPage

    func latestItems(
        in viewID: MediaServerItemID,
        on server: MediaServerAuthenticatedServer,
        limit: Int?
    ) async throws -> [MediaServerLibraryItem]

    func nextUp(
        on server: MediaServerAuthenticatedServer,
        seriesID: MediaServerItemID?,
        startIndex: Int?,
        limit: Int?
    ) async throws -> MediaServerItemPage

    func search(
        _ searchTerm: String,
        on server: MediaServerAuthenticatedServer,
        query: MediaServerItemQuery
    ) async throws -> MediaServerItemPage

    func specialFeatures(
        for itemID: MediaServerItemID,
        on server: MediaServerAuthenticatedServer
    ) async throws -> [MediaServerLibraryItem]

    func similarItems(
        to itemID: MediaServerItemID,
        on server: MediaServerAuthenticatedServer,
        limit: Int?
    ) async throws -> MediaServerItemPage

    func imageURL(
        for itemID: MediaServerItemID,
        type: MediaServerImageType,
        tag: MediaServerImageTag?,
        size: MediaServerImageSize?,
        on server: MediaServerAuthenticatedServer
    ) throws -> URL

    func backdropImageURL(
        for itemID: MediaServerItemID,
        index: Int,
        tag: MediaServerImageTag?,
        size: MediaServerImageSize?,
        on server: MediaServerAuthenticatedServer
    ) throws -> URL

    func playbackInfo(
        for item: MediaServerLibraryItem,
        on server: MediaServerAuthenticatedServer
    ) async throws -> MediaServerPlaybackSession

    func externalSubtitleURL(
        for stream: MediaServerMediaStream,
        on server: MediaServerAuthenticatedServer
    ) throws -> URL

    func sendPlayingStarted(
        _ report: MediaServerPlaybackReport,
        on server: MediaServerAuthenticatedServer
    ) async throws

    func sendProgress(
        _ report: MediaServerPlaybackReport,
        on server: MediaServerAuthenticatedServer
    ) async throws

    func sendStopped(
        _ report: MediaServerPlaybackReport,
        on server: MediaServerAuthenticatedServer
    ) async throws
}

public extension MediaServerClientProtocol {
    var kind: MediaServerKind { .emby }
    var capabilities: MediaServerCapabilities { .all }
    func latestItems(
        in viewID: MediaServerItemID,
        on server: MediaServerAuthenticatedServer,
        limit: Int?
    ) async throws -> [MediaServerLibraryItem] {
        throw MediaServerError.invalidResponse
    }

    func specialFeatures(
        for itemID: MediaServerItemID,
        on server: MediaServerAuthenticatedServer
    ) async throws -> [MediaServerLibraryItem] {
        throw MediaServerError.invalidResponse
    }

    func similarItems(
        to itemID: MediaServerItemID,
        on server: MediaServerAuthenticatedServer,
        limit: Int?
    ) async throws -> MediaServerItemPage {
        throw MediaServerError.invalidResponse
    }

    func backdropImageURL(
        for itemID: MediaServerItemID,
        index: Int,
        tag: MediaServerImageTag?,
        size: MediaServerImageSize?,
        on server: MediaServerAuthenticatedServer
    ) throws -> URL {
        try imageURL(for: itemID, type: .backdrop, tag: tag, size: size, on: server)
    }
}
