import Foundation
import MediaSource
@testable import Emby
import Testing

struct EmbyMediaByteSessionTests {
    @Test("media byte reads default to the session that carries the server trust policy")
    func byteSourceUsesTheTrustedSession() throws {
        let url = try #require(URL(string: "https://192.168.5.28:8920/emby/Videos/1/stream.mkv"))
        let source = EmbyMediaByteSource(
            streamURL: url,
            accessToken: "token",
            contentLength: 1_024
        )

        #expect(source.session === MediaSourceNetwork.shared.session)
    }

    @Test("the shared media session evaluates server trust through the approval policy")
    func sharedSessionCarriesTheTrustDelegate() {
        #expect(MediaSourceNetwork.shared.session.delegate is ServerTrustPolicy)
        #expect((URLSession.shared.delegate is ServerTrustPolicy) == false)
    }
}
