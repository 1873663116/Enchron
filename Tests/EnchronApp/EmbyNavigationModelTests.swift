import MediaServer
import Testing

@Suite("Emby navigation")
@MainActor
struct EmbyNavigationModelTests {
    @Test("Navigation position survives a browser unmount")
    func navigationPositionSurvivesBrowserUnmount() {
        let applicationNavigation = MediaServerNavigationModel()
        var mountedBrowserNavigation: MediaServerNavigationModel? = applicationNavigation
        let libraryID = MediaServerItemID(rawValue: "movies")
        let item = movie(id: "selected-movie")

        mountedBrowserNavigation?.select(.library(libraryID))
        mountedBrowserNavigation?.open(item)
        mountedBrowserNavigation = nil

        let remountedBrowserNavigation = applicationNavigation
        #expect(remountedBrowserNavigation.destination == .library(libraryID))
        #expect(remountedBrowserNavigation.path == [item])
    }

    @Test("Selecting a sidebar destination clears the detail path")
    func sidebarSelectionClearsDetailPath() {
        let navigation = MediaServerNavigationModel()
        navigation.open(movie(id: "selected-movie"))

        navigation.select(.search)

        #expect(navigation.destination == .search)
        #expect(navigation.path.isEmpty)
    }

    @Test("Signing out resets navigation to home")
    func signOutResetsNavigation() async {
        let navigation = MediaServerNavigationModel()
        navigation.select(.library(MediaServerItemID(rawValue: "movies")))
        navigation.open(movie(id: "selected-movie"))
        let session = MediaServerSessionViewModel(
            client: MediaBrowserClient(clientIdentity: MediaServerClientIdentity(
                name: "Enchron tests",
                version: "1",
                deviceName: "Test",
                deviceID: "test"
            )),
            store: EmptyServerStore(),
            navigation: navigation
        )

        await session.signOut()

        #expect(navigation.destination == .home)
        #expect(navigation.path.isEmpty)
    }

    private func movie(id: String) -> MediaServerLibraryItem {
        .movie(MediaServerMovie(metadata: MediaServerItemMetadata(
            id: MediaServerItemID(rawValue: id),
            name: id,
            imageTags: MediaServerImageTags(),
            overview: nil,
            runTimeTicks: nil,
            userData: nil,
            entityTag: nil,
            sizeInBytes: nil
        )))
    }
}

private struct EmptyServerStore: MediaServerServerStoring {
    func loadServer() throws -> MediaServerAuthenticatedServer? { nil }
    func saveServer(_ server: MediaServerAuthenticatedServer) throws {}
    func deleteServer() throws {}
}
