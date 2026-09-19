import MediaSource
import XCTest
@testable import Enchron

nonisolated final class ConnectionSecurityPromptTests: XCTestCase {
    @MainActor
    func testPromptWaitsForPresentedModalDismissal() async {
        let coordinator = AppModalPresentationCoordinator()
        let presentedModal = AppModalPresentationID("source-connection")
        let dismissalRequested = expectation(description: "presented modal dismissal requested")
        coordinator.modalDidPresent(presentedModal) {
            dismissalRequested.fulfill()
        }
        let prompt = ConnectionSecurityPrompt(
            modalPresentationCoordinator: coordinator
        )
        let question = makeCertificateQuestion()

        let approval = Task { await prompt.requestApproval(for: question) }
        await fulfillment(of: [dismissalRequested], timeout: 1)

        XCTAssertNil(prompt.question)

        coordinator.modalDidDismiss(presentedModal)
        let certificateWasPresented = await waitUntil {
            prompt.question != nil
        }

        XCTAssertTrue(certificateWasPresented)
        XCTAssertEqual(prompt.question, question)
        prompt.resolve(approved: true)
        let wasApproved = await approval.value
        XCTAssertTrue(wasApproved)
    }

    @MainActor
    func testPromptReturnsCancellation() async {
        let prompt = ConnectionSecurityPrompt(
            modalPresentationCoordinator: AppModalPresentationCoordinator()
        )
        let question = makeCertificateQuestion()

        let approval = Task { await prompt.requestApproval(for: question) }
        let certificateWasPresented = await waitUntil {
            prompt.question != nil
        }
        XCTAssertTrue(certificateWasPresented)

        prompt.resolve(approved: false)

        let wasApproved = await approval.value
        XCTAssertFalse(wasApproved)
        XCTAssertNil(prompt.question)
    }

    private func makeCertificateQuestion() -> ConnectionSecurityQuestion {
        .unverifiedCertificate(.firstContact(makeCertificate()))
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

nonisolated final class ConnectionSecurityQuestionWordingTests: XCTestCase {
    @MainActor private func titleOf(_ question: ConnectionSecurityQuestion) -> String {
        String(localized: question.title)
    }

    @MainActor private func messageOf(_ question: ConnectionSecurityQuestion) -> String {
        String(describing: question.message)
    }

    @MainActor
    func testAReplacedCertificateIsNotWordedAsAFirstContact() {
        let certificate = ServerCertificateInfo(
            address: "media.local:5006",
            certificateName: "media.local",
            sha256Fingerprint: "AA:BB",
            validFrom: nil,
            validUntil: nil
        )
        let firstContact = ConnectionSecurityQuestion
            .unverifiedCertificate(.firstContact(certificate))
        let replacement = ConnectionSecurityQuestion
            .unverifiedCertificate(.replacement(certificate, previousFingerprint: "CC:DD"))

        XCTAssertEqual(titleOf(firstContact), "Cannot verify the server certificate")
        XCTAssertEqual(titleOf(replacement), "The server certificate has changed")
        XCTAssertFalse(messageOf(firstContact).contains("CC:DD"))
        XCTAssertTrue(messageOf(replacement).contains("CC:DD"))
        XCTAssertTrue(messageOf(replacement).contains("AA:BB"))
    }

    @MainActor
    func testTheCleartextQuestionNamesTheHostAndTheRemedy() {
        let question = ConnectionSecurityQuestion.cleartextCredentials(host: "203.0.113.92")

        XCTAssertEqual(
            titleOf(question),
            "This address will not encrypt your password"
        )
        let description = messageOf(question)
        XCTAssertTrue(description.contains("203.0.113.92"))
        XCTAssertTrue(description.contains("https://"))
    }
}
