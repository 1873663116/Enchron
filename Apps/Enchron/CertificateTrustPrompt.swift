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
            active = queue.removeFirst()
            isPreparingPresentation = false
        }
    }
}
