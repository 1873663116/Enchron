import Foundation
@testable import MediaSource
import Testing

@MainActor
private final class ServerTrustPolicyRecorder {
    var approvalRequestCount = 0
    var certificateChanges: [ServerCertificateChange] = []
}

struct ServerTrustPolicyTests {
    @Test("a certificate that replaced an approved one is reported without asking")
    @MainActor
    func aReplacedCertificateIsReportedWithoutAsking() async throws {
        let suiteName = "ServerTrustPolicyTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let address = "media.example:443"
        let previousFingerprint = "AA:BB:CC"
        let currentFingerprint = "DD:EE:FF"
        let recorder = ServerTrustPolicyRecorder()
        let policy = ServerTrustPolicy(defaults: defaults)
        policy.approvalHandler = { _ in
            recorder.approvalRequestCount += 1
            return true
        }
        policy.certificateChangeHandler = {
            recorder.certificateChanges.append($0)
        }

        let mayAsk = policy.reportUntrustedCertificate(
            address: address,
            currentFingerprint: currentFingerprint,
            previousFingerprint: previousFingerprint
        )
        await Task.yield()

        #expect(mayAsk == false)
        #expect(recorder.approvalRequestCount == 0)
        #expect(
            recorder.certificateChanges == [
                ServerCertificateChange(
                    address: address,
                    previousFingerprint: previousFingerprint,
                    currentFingerprint: currentFingerprint
                )
            ]
        )
    }

    @Test("a certificate seen for the first time reports no change")
    @MainActor
    func aFirstContactCertificateReportsNoChange() async throws {
        let suiteName = "ServerTrustPolicyTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let recorder = ServerTrustPolicyRecorder()
        let policy = ServerTrustPolicy(defaults: defaults)
        policy.certificateChangeHandler = {
            recorder.certificateChanges.append($0)
        }

        let mayAsk = policy.reportUntrustedCertificate(
            address: "new.example:443",
            currentFingerprint: "11:22:33",
            previousFingerprint: nil
        )
        await Task.yield()

        #expect(mayAsk == false)
        #expect(recorder.certificateChanges.isEmpty)
    }

    @Test("the wearer is asked only inside a connection approval")
    @MainActor
    func theWearerIsAskedOnlyInsideAConnectionApproval() async throws {
        let suiteName = "ServerTrustPolicyTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let recorder = ServerTrustPolicyRecorder()
        let policy = ServerTrustPolicy(defaults: defaults)
        policy.certificateChangeHandler = {
            recorder.certificateChanges.append($0)
        }

        let inside = try await policy.withConnectionApproval(
            to: try #require(URL(string: "https://media.example"))
        ) {
            policy.reportUntrustedCertificate(
                address: "media.example:443",
                currentFingerprint: "DD:EE:FF",
                previousFingerprint: "AA:BB:CC"
            )
        }
        let outside = policy.reportUntrustedCertificate(
            address: "media.example:443",
            currentFingerprint: "DD:EE:FF",
            previousFingerprint: "AA:BB:CC"
        )
        await Task.yield()

        #expect(inside == true)
        #expect(outside == false)
        #expect(recorder.certificateChanges.count == 2)
    }
}
