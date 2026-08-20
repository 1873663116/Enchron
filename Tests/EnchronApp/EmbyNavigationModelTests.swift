import Emby
import Testing

@Suite("Emby navigation")
@MainActor
struct EmbyNavigationModelTests {
    @Test("Navigation position survives a browser unmount")
    func navigationPositionSurvivesBrowserUnmount() {
        let applicationNavigation = EmbyNavigationModel()
        var mountedBrowserNavigation: EmbyNavigationModel? = applicationNavigation
        let libraryID = EmbyItemID(rawValue: "movies")
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
        let navigation = EmbyNavigationModel()
        navigation.open(movie(id: "selected-movie"))

        navigation.select(.search)

        #expect(navigation.destination == .search)
        #expect(navigation.path.isEmpty)
    }

    @Test("Signing out resets navigation to home")
    func signOutResetsNavigation() async {
        let navigation = EmbyNavigationModel()
        navigation.select(.library(EmbyItemID(rawValue: "movies")))
        navigation.open(movie(id: "selected-movie"))
        let session = EmbySessionViewModel(
            client: EmbyClient(clientIdentity: EmbyClientIdentity(
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

    private func movie(id: String) -> EmbyLibraryItem {
        .movie(EmbyMovie(metadata: EmbyItemMetadata(
            id: EmbyItemID(rawValue: id),
            name: id,
            imageTags: EmbyImageTags(),
            overview: nil,
            runTimeTicks: nil,
            userData: nil,
            entityTag: nil,
            sizeInBytes: nil
        )))
    }
}

private struct EmptyServerStore: EmbyServerStoring {
    func loadServer() throws -> EmbyAuthenticatedServer? { nil }
    func saveServer(_ server: EmbyAuthenticatedServer) throws {}
    func deleteServer() throws {}
}
