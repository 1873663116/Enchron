import Foundation
import MediaLibrary
import MediaSource
import XCTest

nonisolated final class RemoteConnectionFailureDiagnoserTests: XCTestCase {
    func testATSBlockRequiresHTTPSWithoutAProbe() async throws {
        let recorder = TLSProbeRecorder(result: true)
        let diagnoser = MediaSource.RemoteConnectionFailureDiagnoser { endpoint in
            await recorder.probe(endpoint)
        }
        let url = try XCTUnwrap(URL(string: "http://media.example.com:8096"))

        let diagnosis = await diagnoser.diagnose(
            URLError(.appTransportSecurityRequiresSecureConnection),
            attemptedURL: url
        )

        XCTAssertEqual(diagnosis, .requiresHTTPS)
        let probedEndpoints = await recorder.endpoints
        XCTAssertEqual(probedEndpoints, [])
    }

    func testPlainHTTPTransportFailureUsesExactEndpointTLSProbe() async throws {
        let recorder = TLSProbeRecorder(result: true)
        let diagnoser = MediaSource.RemoteConnectionFailureDiagnoser { endpoint in
            await recorder.probe(endpoint)
        }
        let url = try XCTUnwrap(URL(string: "http://media.local:5006/library"))

        let diagnosis = await diagnoser.diagnose(
            URLError(.cannotConnectToHost),
            attemptedURL: url
        )

        XCTAssertEqual(diagnosis, .requiresHTTPS)
        let probedEndpoints = await recorder.endpoints
        XCTAssertEqual(
            probedEndpoints,
            [MediaSource.RemoteConnectionEndpoint(host: "media.local", port: 5_006)]
        )
    }

    func testFailedTLSProbePreservesTheOriginalFailureClassification() async throws {
        let recorder = TLSProbeRecorder(result: false)
        let diagnoser = MediaSource.RemoteConnectionFailureDiagnoser { endpoint in
            await recorder.probe(endpoint)
        }
        let url = try XCTUnwrap(URL(string: "http://offline.local:8080"))

        let diagnosis = await diagnoser.diagnose(
            URLError(.timedOut),
            attemptedURL: url
        )

        XCTAssertEqual(diagnosis, .serverUnreachable)
        let probedEndpoints = await recorder.endpoints
        XCTAssertEqual(
            probedEndpoints,
            [MediaSource.RemoteConnectionEndpoint(host: "offline.local", port: 8_080)]
        )
    }

    func testExplicitHTTPSFailureDoesNotRunThePlaintextProbe() async throws {
        let recorder = TLSProbeRecorder(result: true)
        let diagnoser = MediaSource.RemoteConnectionFailureDiagnoser { endpoint in
            await recorder.probe(endpoint)
        }
        let url = try XCTUnwrap(URL(string: "https://offline.local:8443"))

        let diagnosis = await diagnoser.diagnose(
            URLError(.cannotConnectToHost),
            attemptedURL: url
        )

        XCTAssertEqual(diagnosis, .serverUnreachable)
        let probedEndpoints = await recorder.endpoints
        XCTAssertEqual(probedEndpoints, [])
    }

    func testAuthenticationURLFailureIsCredentialsRejected() async throws {
        let diagnoser = MediaSource.RemoteConnectionFailureDiagnoser { _ in
            XCTFail("HTTPS URLs must not trigger the plaintext TLS probe")
            return false
        }
        let url = try XCTUnwrap(URL(string: "https://media.example.test"))

        let diagnosis = await diagnoser.diagnose(
            URLError(.userAuthenticationRequired),
            attemptedURL: url
        )

        XCTAssertEqual(diagnosis, .credentialsRejected)
    }

    func testMalformedURLFailureIsInvalidAddress() async throws {
        let diagnoser = MediaSource.RemoteConnectionFailureDiagnoser { _ in
            XCTFail("HTTPS URLs must not trigger the plaintext TLS probe")
            return false
        }
        let url = try XCTUnwrap(URL(string: "https://media.example.test"))

        let diagnosis = await diagnoser.diagnose(
            URLError(.badURL),
            attemptedURL: url
        )

        XCTAssertEqual(diagnosis, .invalidAddress)
    }

    func testNonURLFailureUsesTheClosedFallback() async throws {
        let recorder = TLSProbeRecorder(result: true)
        let diagnoser = MediaSource.RemoteConnectionFailureDiagnoser { endpoint in
            await recorder.probe(endpoint)
        }
        let url = try XCTUnwrap(URL(string: "https://media.example.test"))

        let diagnosis = await diagnoser.diagnose(
            CocoaError(.fileReadCorruptFile),
            attemptedURL: url
        )

        XCTAssertEqual(diagnosis, .serverUnreachable)
        let probedEndpoints = await recorder.endpoints
        XCTAssertEqual(probedEndpoints, [])
    }

    func testPresentationCopyGivesEachFailureAnActionableMessage() {
        XCTAssertEqual(
            MediaSource.RemoteConnectionFailure.credentialsRejected.sourceConnectionMessage,
            "Credentials rejected. Check your username and password."
        )
        XCTAssertEqual(
            MediaSource.RemoteConnectionFailure.serverUnreachable.sourceConnectionMessage,
            "Server unreachable. Check the address and your network connection."
        )
        XCTAssertEqual(
            MediaSource.RemoteConnectionFailure.invalidAddress.sourceConnectionMessage,
            "Invalid address. Check the server address and try again."
        )
        XCTAssertEqual(
            MediaSource.RemoteConnectionFailure.requiresHTTPS.sourceConnectionMessage,
            "This server requires HTTPS. Add https:// to the address and try again."
        )
    }
}

private actor TLSProbeRecorder {
    private(set) var endpoints: [MediaSource.RemoteConnectionEndpoint] = []
    private let result: Bool

    init(result: Bool) {
        self.result = result
    }

    func probe(_ endpoint: MediaSource.RemoteConnectionEndpoint) -> Bool {
        endpoints.append(endpoint)
        return result
    }
}
