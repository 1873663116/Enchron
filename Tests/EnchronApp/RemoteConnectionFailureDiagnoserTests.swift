import Foundation
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
        XCTAssertEqual(
            MediaSource.RemoteConnectionError.requiresHTTPS.localizedDescription,
            "该地址需要使用 HTTPS。请在服务器地址前添加 https:// 后重试。"
        )
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

        XCTAssertEqual(diagnosis, .unclassified)
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

        XCTAssertEqual(diagnosis, .unclassified)
        let probedEndpoints = await recorder.endpoints
        XCTAssertEqual(probedEndpoints, [])
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
