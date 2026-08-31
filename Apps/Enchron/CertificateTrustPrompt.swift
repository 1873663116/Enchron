import Foundation
import MediaSource
import Observation
import Playback

@MainActor
@Observable
final class CertificateTrustPrompt {
    private struct PendingRequest {
        let certificate: ServerCertificateInfo
        let continuation: CheckedContinuation<Bool, Never>
    }

    private var queue: [PendingRequest] = []
    private var active: PendingRequest?
    private var isPreparingPresentation = false
    private let modalPresentationCoordinator: AppModalPresentationCoordinator

    var certificate: ServerCertificateInfo? { active?.certificate }

    init(modalPresentationCoordinator: AppModalPresentationCoordinator) {
        self.modalPresentationCoordinator = modalPresentationCoordinator
    }

    func requestApproval(for certificate: ServerCertificateInfo) async -> Bool {
        await withCheckedContinuation { continuation in
            queue.append(PendingRequest(certificate: certificate, continuation: continuation))
            presentNextIfNeeded()
        }
    }

    func resolve(approved: Bool) {
        guard let active else { return }
        SurfaceInputProbes.record(
            "certificateBoundary decision approved=\(approved)"
                + " address=\(active.certificate.address)"
                + " fingerprint=\(active.certificate.sha256Fingerprint)",
            retention: .evidence
        )
        self.active = nil
        active.continuation.resume(returning: approved)
        presentNextIfNeeded()
    }

    private func presentNextIfNeeded() {
        guard active == nil,
              isPreparingPresentation == false,
              queue.isEmpty == false else { return }
        isPreparingPresentation = true
        Task { [weak self] in
            guard let self else { return }
            await modalPresentationCoordinator
                .dismissPresentedModalBeforePresentingNext()
            guard active == nil, queue.isEmpty == false else {
                isPreparingPresentation = false
                return
            }
            let request = queue.removeFirst()
            active = request
            SurfaceInputProbes.record(
                "certificateBoundary promptPresented"
                    + " address=\(request.certificate.address)"
                    + " name=\(request.certificate.certificateName)"
                    + " fingerprint=\(request.certificate.sha256Fingerprint)"
                    + " validFrom=\(request.certificate.validFrom?.timeIntervalSince1970.description ?? "none")"
                    + " validUntil=\(request.certificate.validUntil?.timeIntervalSince1970.description ?? "none")",
                retention: .evidence
            )
            isPreparingPresentation = false
        }
    }
}
