import MediaSource
import XCTest
@testable import Enchron

nonisolated final class CertificateTrustPromptTests: XCTestCase {
    @MainActor
    func testPromptWaitsForPresentedModalDismissal() async {
        let coordinator = AppModalPresentationCoordinator()
        let presentedModal = AppModalPresentationID("source-connection")
        let dismissalRequested = expectation(description: "presented modal dismissal requested")
        coordinator.modalDidPresent(presentedModal) {
            dismissalRequested.fulfill()
        }
        let prompt = CertificateTrustPrompt(
            modalPresentationCoordinator: coordinator
        )
        let certificate = makeCertificate()

        let approval = Task { await prompt.requestApproval(for: certificate) }
        await fulfillment(of: [dismissalRequested], timeout: 1)

        XCTAssertNil(prompt.certificate)

        coordinator.modalDidDismiss(presentedModal)
        let certificateWasPresented = await waitUntil {
            prompt.certificate != nil
        }

        XCTAssertTrue(certificateWasPresented)
        XCTAssertEqual(prompt.certificate, certificate)
        prompt.resolve(approved: true)
        let wasApproved = await approval.value
        XCTAssertTrue(wasApproved)
    }

    @MainActor
    func testPromptReturnsCancellation() async {
        let prompt = CertificateTrustPrompt(
            modalPresentationCoordinator: AppModalPresentationCoordinator()
        )
        let certificate = makeCertificate()

        let approval = Task { await prompt.requestApproval(for: certificate) }
        let certificateWasPresented = await waitUntil {
            prompt.certificate != nil
        }
        XCTAssertTrue(certificateWasPresented)

        prompt.resolve(approved: false)

        let wasApproved = await approval.value
        XCTAssertFalse(wasApproved)
        XCTAssertNil(prompt.certificate)
    }

    private func makeCertificate() -> ServerCertificateInfo {
        ServerCertificateInfo(
            address: "media.local:5006",
            certificateName: "media.local",
            sha256Fingerprint: "AA:BB",
            validFrom: nil,
            validUntil: nil
        )
    }

    @MainActor
    private func waitUntil(
        _ condition: @escaping @MainActor () -> Bool
    ) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(1))
        while condition() == false {
            guard clock.now < deadline else { return false }
            await Task.yield()
        }
        return true
    }
}
