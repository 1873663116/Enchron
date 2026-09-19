import Foundation
import MediaSource
import Observation
import Playback
import SwiftUI

enum ConnectionSecurityQuestion: Equatable {
    case unverifiedCertificate(ServerCertificateApproval)
    case cleartextCredentials(host: String)

    var probeIdentity: String {
        switch self {
        case .unverifiedCertificate(let approval):
            "certificateBoundary address=\(approval.certificate.address)"
                + " fingerprint=\(approval.certificate.sha256Fingerprint)"
        case .cleartextCredentials(let host):
            "cleartextBoundary host=\(host)"
        }
    }

    var title: LocalizedStringResource {
        switch self {
        case .cleartextCredentials:
            "This address will not encrypt your password"
        case .unverifiedCertificate(.replacement):
            "The server certificate has changed"
        case .unverifiedCertificate(.firstContact):
            "Cannot verify the server certificate"
        }
    }

    var message: Text {
        switch self {
        case .cleartextCredentials(let host):
            Text("""
                \(host) is outside your local network, so requests to its http:// address \
                travel over the public internet. Your username and password are sent \
                unencrypted, and any device on the path can read them. Use https:// or a \
                private encrypted network instead.
                """
            )
        case .unverifiedCertificate(.firstContact(let certificate)):
            certificate.summary
        case .unverifiedCertificate(.replacement(let certificate, let previousFingerprint)):
            Text("""
                You approved a different certificate for this address before. Unless the \
                server changed certificates recently, this one may come from something \
                impersonating it.
                """
            )
            + Text("\n\n")
            + certificate.summary
            + Text("\n\n")
            + Text("Previously approved fingerprint: \(previousFingerprint)")
        }
    }
}

private extension ServerCertificateInfo {
    var summary: Text {
        let validFrom = validFrom?.formatted(date: .abbreviated, time: .shortened)
            ?? String(localized: "Unknown")
        let validUntil = validUntil?.formatted(date: .abbreviated, time: .shortened)
            ?? String(localized: "Unknown")
        return Text("""
            Address: \(address)
            Certificate: \(certificateName)
            Fingerprint: \(sha256Fingerprint)
            Valid: \(validFrom) – \(validUntil)
            """
        )
    }
}

@MainActor
@Observable
final class ConnectionSecurityPrompt {
    private struct PendingRequest {
        let question: ConnectionSecurityQuestion
        let continuation: CheckedContinuation<Bool, Never>
    }

    private var queue: [PendingRequest] = []
    private var active: PendingRequest?
    private var isPreparingPresentation = false
    private let modalPresentationCoordinator: AppModalPresentationCoordinator

    var question: ConnectionSecurityQuestion? { active?.question }

    init(modalPresentationCoordinator: AppModalPresentationCoordinator) {
        self.modalPresentationCoordinator = modalPresentationCoordinator
    }

    func requestApproval(for question: ConnectionSecurityQuestion) async -> Bool {
        await withCheckedContinuation { continuation in
            queue.append(PendingRequest(question: question, continuation: continuation))
            presentNextIfNeeded()
        }
    }

    func resolve(approved: Bool) {
        guard let active else { return }
        SurfaceInputProbes.record(
            "certificateBoundary decision approved=\(approved)"
                + " \(active.question.probeIdentity)",
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
                "certificateBoundary promptPresented \(request.question.probeIdentity)",
                retention: .evidence
            )
            isPreparingPresentation = false
        }
    }
}
