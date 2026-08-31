import Foundation
@testable import MediaSource
import Testing

@MainActor
private final class ServerTrustPolicyRecorder {
    var approvalRequestCount = 0
    var certificateChanges: [ServerCertificateChange] = []
}

struct ServerTrustPolicyTests {
    @Test("stored certificate changes reject once without approval or trust mutation")
    @MainActor
    func storedCertificateChangesRejectOnceWithoutApprovalOrTrustMutation() async throws {
        let suiteName = "ServerTrustPolicyTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let address = "media.example:443"
        let previousFingerprint = "AA:BB:CC"
        let currentFingerprint = "DD:EE:FF"
        let fingerprintKey = "server-certificate-fingerprint.\(address)"
        defaults.set(previousFingerprint, forKey: fingerprintKey)
        let recorder = ServerTrustPolicyRecorder()
        let policy = ServerTrustPolicy(defaults: defaults)
        policy.approvalHandler = { _ in
            recorder.approvalRequestCount += 1
            return true
        }
        policy.certificateChangeHandler = {
            recorder.certificateChanges.append($0)
        }

        let approvalDecision = try await policy.withConnectionApproval(
            to: try #require(URL(string: "https://media.example"))
        ) {
            policy.resolveUntrustedCertificate(
                address: address,
                currentFingerprint: currentFingerprint
            )
        }
        #expect(approvalDecision == .requestApproval)
        #expect(recorder.certificateChanges.isEmpty)

        let firstDecision = policy.resolveUntrustedCertificate(
            address: address,
            currentFingerprint: currentFingerprint
        )
        let repeatedDecision = policy.resolveUntrustedCertificate(
            address: address,
            currentFingerprint: currentFingerprint
        )
        await Task.yield()

        #expect(firstDecision == .reject)
        #expect(repeatedDecision == .reject)
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
        #expect(defaults.string(forKey: fingerprintKey) == previousFingerprint)
    }

    @Test("untrusted certificates without a stored trust boundary reject silently")
    @MainActor
    func untrustedCertificatesWithoutStoredTrustRejectSilently() async throws {
        let suiteName = "ServerTrustPolicyTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let recorder = ServerTrustPolicyRecorder()
        let policy = ServerTrustPolicy(defaults: defaults)
        policy.certificateChangeHandler = {
            recorder.certificateChanges.append($0)
        }

        let decision = policy.resolveUntrustedCertificate(
            address: "new.example:443",
            currentFingerprint: "11:22:33"
        )
        await Task.yield()

        #expect(decision == .reject)
        #expect(recorder.certificateChanges.isEmpty)
    }
}
