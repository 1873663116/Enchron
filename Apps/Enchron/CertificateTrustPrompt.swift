import MediaSource
import Observation

@MainActor
@Observable
final class CertificateTrustPrompt {
    private struct PendingRequest {
        let certificate: ServerCertificateInfo
        let continuation: CheckedContinuation<Bool, Never>
    }

    private var queue: [PendingRequest] = []
    private var active: PendingRequest?

    var certificate: ServerCertificateInfo? { active?.certificate }

    func requestApproval(for certificate: ServerCertificateInfo) async -> Bool {
        await withCheckedContinuation { continuation in
            queue.append(PendingRequest(certificate: certificate, continuation: continuation))
            presentNextIfNeeded()
        }
    }

    func resolve(approved: Bool) {
        guard let active else { return }
        self.active = nil
        active.continuation.resume(returning: approved)
        presentNextIfNeeded()
    }

    private func presentNextIfNeeded() {
        guard active == nil, queue.isEmpty == false else { return }
        active = queue.removeFirst()
    }
}
