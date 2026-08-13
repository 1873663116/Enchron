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

    func latestItems(
        in viewID: EmbyItemID,
        on server: EmbyAuthenticatedServer,
        limit: Int?
    ) async throws -> [EmbyLibraryItem]

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

    func specialFeatures(
        for itemID: EmbyItemID,
        on server: EmbyAuthenticatedServer
    ) async throws -> [EmbyLibraryItem]

    func similarItems(
        to itemID: EmbyItemID,
        on server: EmbyAuthenticatedServer,
        limit: Int?
    ) async throws -> EmbyItemPage

    func imageURL(
        for itemID: EmbyItemID,
        type: EmbyImageType,
        tag: EmbyImageTag?,
        size: EmbyImageSize?,
        on server: EmbyAuthenticatedServer
    ) throws -> URL

    func backdropImageURL(
        for itemID: EmbyItemID,
        index: Int,
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

public extension EmbyClientProtocol {
    func latestItems(
        in viewID: EmbyItemID,
        on server: EmbyAuthenticatedServer,
        limit: Int?
    ) async throws -> [EmbyLibraryItem] {
        throw EmbyError.invalidResponse
    }

    func specialFeatures(
        for itemID: EmbyItemID,
        on server: EmbyAuthenticatedServer
    ) async throws -> [EmbyLibraryItem] {
        throw EmbyError.invalidResponse
    }

    func similarItems(
        to itemID: EmbyItemID,
        on server: EmbyAuthenticatedServer,
        limit: Int?
    ) async throws -> EmbyItemPage {
        throw EmbyError.invalidResponse
    }

    func backdropImageURL(
        for itemID: EmbyItemID,
        index: Int,
        tag: EmbyImageTag?,
        size: EmbyImageSize?,
        on server: EmbyAuthenticatedServer
    ) throws -> URL {
        try imageURL(for: itemID, type: .backdrop, tag: tag, size: size, on: server)
    }
}
