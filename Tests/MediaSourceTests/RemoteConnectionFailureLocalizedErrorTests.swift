import Foundation
import MediaSource
import Testing

struct RemoteConnectionFailureLocalizedErrorTests {
    @Test("remote connection failures provide stable friendly descriptions")
    func localizedDescriptions() {
        let descriptions: [(RemoteConnectionFailure, String)] = [
            (
                .credentialsRejected,
                "Credentials rejected. Check your username and password."
            ),
            (
                .serverUnreachable,
                "Server unreachable. Check the address and your network connection."
            ),
            (
                .invalidAddress,
                "Invalid address. Check the server address and try again."
            ),
            (
                .requiresHTTPS,
                "This server requires HTTPS. Add https:// to the address and try again."
            )
        ]

        for (failure, expectedDescription) in descriptions {
            #expect(failure.localizedDescription == expectedDescription)
        }
    }
}
