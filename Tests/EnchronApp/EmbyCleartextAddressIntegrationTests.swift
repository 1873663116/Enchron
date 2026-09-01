import Foundation
@testable import Emby
import XCTest

nonisolated final class EmbyCleartextAddressIntegrationTests: XCTestCase {
    func testAuthenticatesOverCleartextHTTPToARoutableIPAddress() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let rawAddress = environment["ENCHRON_EMBY_TEST_URL"],
              let username = environment["ENCHRON_EMBY_TEST_USERNAME"],
              let password = environment["ENCHRON_EMBY_TEST_PASSWORD"] else {
            throw XCTSkip("Set the ENCHRON_EMBY_TEST_* environment variables to run the live cleartext Emby test.")
        }
        let address = try XCTUnwrap(URL(string: rawAddress))
        XCTAssertEqual(
            address.scheme,
            "http",
            "ENCHRON_EMBY_TEST_URL must be cleartext; an https address exercises no transport policy."
        )
        let host = try XCTUnwrap(address.host)
        let literal = try XCTUnwrap(
            IPv4Literal(host),
            "ENCHRON_EMBY_TEST_URL must name an IP address; a hostname is exempt for other reasons."
        )
        XCTAssertFalse(
            literal.isCoveredByLocalNetworkingExemption,
            "\(host) loads even under NSAllowsLocalNetworking, so it cannot show whether cleartext is permitted."
        )

        let client = EmbyClient(
            clientIdentity: EmbyClientIdentity(
                name: "Enchron",
                version: "1",
                deviceName: "Cleartext Address Tests",
                deviceID: "enchron-cleartext-address-tests"
            )
        )
        let server = try await client.authenticate(
            address: address,
            username: username,
            password: password
        )

        XCTAssertFalse(server.accessToken.isEmpty)
        XCTAssertEqual(server.baseAddress.scheme, "http")
    }
}

private nonisolated struct IPv4Literal {
    private let octets: [UInt8]

    init?(_ host: String) {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        let parsed = parts.compactMap { UInt8($0) }
        guard parsed.count == 4 else { return nil }
        octets = parsed
    }

    var isCoveredByLocalNetworkingExemption: Bool {
        switch (octets[0], octets[1]) {
        case (127, _), (10, _): true
        case (172, 16...31): true
        case (192, 168), (169, 254): true
        default: false
        }
    }
}
