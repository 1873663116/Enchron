import Foundation
import Testing
@testable import Emby

struct EmbyDecodingTests {
    @Test("live public system info fixture decodes into the domain model")
    func publicSystemInfoFixture() throws {
        let data = try Data(contentsOf: #require(Bundle.module.url(
            forResource: "PublicSystemInfo",
            withExtension: "json"
        )))
        let info = try JSONDecoder().decode(EmbyPublicSystemInfo.self, from: data)

        #expect(info.version == "4.9.5.0")
        #expect(info.serverName == "Mac-mini")
    }

    @Test("live public users fixture decodes without an access token")
    func publicUsersFixture() throws {
        let url = try #require(Bundle.module.url(forResource: "PublicUsers", withExtension: "json"))
        let data = try Data(contentsOf: url)
        let users = try JSONDecoder().decode([EmbyPublicUser].self, from: data)

        #expect(users.map(\.name) == ["Cortisol"])
        #expect(!String(decoding: data, as: UTF8.self).localizedCaseInsensitiveContains("token"))
    }
}
