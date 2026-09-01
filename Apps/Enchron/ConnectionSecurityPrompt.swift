import Foundation
import MediaSource
import Observation

enum ConnectionSecurityQuestion: Equatable {
    case unverifiedCertificate(ServerCertificateApproval)
    case cleartextCredentials(host: String)

    var title: String {
        switch self {
        case .cleartextCredentials:
            "这个地址不会加密你的密码"
        case .unverifiedCertificate(.replacement):
            "服务器证书已更换"
        case .unverifiedCertificate(.firstContact):
            "无法验证服务器证书"
        }
    }

    var message: String {
        switch self {
        case .cleartextCredentials(let host):
            """
            \(host) 不在局域网内，连接它的 http:// 请求会经过公网。\
            你的用户名和密码会以未加密的形式传输，路径上的任何设备都能读到。
            改用 https:// 或经由加密的专用网络访问可以避免这一点。
            """
        case .unverifiedCertificate(.firstContact(let certificate)):
            certificate.description
        case .unverifiedCertificate(.replacement(let certificate, let previousFingerprint)):
            """
            你以前批准过这个地址的另一张证书。若服务器最近没有更换证书，\
            这次的证书可能来自冒充它的一方。
            \(certificate.description)
            上次批准的指纹：\(previousFingerprint)
            """
        }
    }
}

private extension ServerCertificateInfo {
    var description: String {
        let validFrom = validFrom?.formatted(date: .abbreviated, time: .shortened) ?? "未知"
        let validUntil = validUntil?.formatted(date: .abbreviated, time: .shortened) ?? "未知"
        return "地址：\(address)\n证书名：\(certificateName)\n指纹：\(sha256Fingerprint)\n有效期：\(validFrom) – \(validUntil)"
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
