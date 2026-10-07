import Foundation
import Observation
import Playback
import SwiftUI

@MainActor
public final class MediaServerFeature {
    public let navigation: MediaServerNavigationModel
    public let session: MediaServerSessionViewModel
    public let connection: MediaServerConnectionViewModel
    public let home: MediaServerHomeViewModel
    public let search: MediaServerSearchViewModel

    public init(client: any MediaServerClientProtocol) {
        navigation = MediaServerNavigationModel()
        session = MediaServerSessionViewModel(
            client: client,
            store: KeychainMediaServerStore(sourceID: client.kind.credentialKey),
            navigation: navigation
        )
        connection = MediaServerConnectionViewModel(session: session)
        home = MediaServerHomeViewModel(client: client, session: session)
        search = MediaServerSearchViewModel(client: client, session: session)
    }
}

@MainActor
@Observable
public final class MediaServerSources {
    public let jellyfin: MediaServerFeature
    public let plex: MediaServerFeature
    public var playbackSession: MediaServerSessionViewModel

    public init(embySession: MediaServerSessionViewModel, identity: MediaServerClientIdentity) {
        playbackSession = embySession
        jellyfin = MediaServerFeature(client: MediaBrowserClient(dialect: .jellyfin, clientIdentity: identity))
        plex = MediaServerFeature(client: PlexClient(clientIdentity: identity))
    }
}

public struct MediaServerFeatureScreen: View {
    private let feature: MediaServerFeature
    private let onPlay: MediaServerScreen.PlayHandler

    public init(feature: MediaServerFeature, onPlay: @escaping MediaServerScreen.PlayHandler) {
        self.feature = feature
        self.onPlay = onPlay
    }

    public var body: some View {
        MediaServerScreen(onPlay: onPlay)
            .environment(feature.navigation)
            .environment(feature.session)
            .environment(feature.connection)
            .environment(feature.home)
            .environment(feature.search)
            .task {
                if feature.session.server != nil, feature.home.shelves.isEmpty {
                    await feature.home.refresh()
                }
            }
    }
}
