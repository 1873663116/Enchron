import Foundation

public protocol EmbyClientProtocol: Sendable {
    func authenticate(
        address: URL,
        username: String,
        password: String
    ) async throws -> EmbyAuthenticatedServer

    func views(on server: EmbyAuthenticatedServer) async throws -> [EmbyLibraryView]

    func items(
        in viewID: EmbyItemID,
        on server: EmbyAuthenticatedServer,
        query: EmbyItemQuery
    ) async throws -> EmbyItemPage

    func item(
        withID itemID: EmbyItemID,
        on server: EmbyAuthenticatedServer
    ) async throws -> EmbyLibraryItem

    func children(
        of parent: EmbyLibraryItem,
        on server: EmbyAuthenticatedServer,
        query: EmbyItemQuery
    ) async throws -> EmbyItemPage

    func resumeItems(
        on server: EmbyAuthenticatedServer,
        query: EmbyItemQuery
    ) async throws -> EmbyItemPage

    func nextUp(
        on server: EmbyAuthenticatedServer,
        seriesID: EmbyItemID?,
        startIndex: Int?,
        limit: Int?
    ) async throws -> EmbyItemPage

    func search(
        _ searchTerm: String,
        on server: EmbyAuthenticatedServer,
        query: EmbyItemQuery
    ) async throws -> EmbyItemPage

    func imageURL(
        for itemID: EmbyItemID,
        type: EmbyImageType,
        tag: EmbyImageTag?,
        size: EmbyImageSize?,
        on server: EmbyAuthenticatedServer
    ) throws -> URL

    func playbackInfo(
        for item: EmbyLibraryItem,
        on server: EmbyAuthenticatedServer
    ) async throws -> EmbyPlaybackSession

    func externalSubtitleURL(
        for stream: EmbyMediaStream,
        on server: EmbyAuthenticatedServer
    ) throws -> URL

    func sendPlayingStarted(
        _ report: EmbyPlaybackReport,
        on server: EmbyAuthenticatedServer
    ) async throws

    func sendProgress(
        _ report: EmbyPlaybackReport,
        on server: EmbyAuthenticatedServer
    ) async throws

    func sendStopped(
        _ report: EmbyPlaybackReport,
        on server: EmbyAuthenticatedServer
    ) async throws
}
