import GameStreaming
import XCTest

nonisolated final class StreamCapabilityTests: XCTestCase {
    func testAHostThatDeclaresNothingIsTreatedAsUndeclared() {
        let capabilities = StreamHostCapabilities(serverCodecModeSupport: 0)
        XCTAssertFalse(capabilities.declaresHEVC)
        XCTAssertFalse(capabilities.declaresHDR)
        XCTAssertFalse(capabilities.declaresAV1)
        XCTAssertFalse(capabilities.hasAnyDeclaration)
    }

    func testTheDeclaredBitsFollowTheServerCodecModeValue() {
        let hevc = StreamHostCapabilities(serverCodecModeSupport: 0x01)
        XCTAssertTrue(hevc.declaresHEVC)
        XCTAssertFalse(hevc.declaresHDR)

        let hdr = StreamHostCapabilities(serverCodecModeSupport: 0x02)
        XCTAssertTrue(hdr.declaresHDR)
        XCTAssertFalse(hdr.declaresHEVC)

        let av1 = StreamHostCapabilities(serverCodecModeSupport: 0x04)
        XCTAssertTrue(av1.declaresAV1)
        XCTAssertFalse(av1.declaresAV1 && av1.declaresHEVC)

        let everything = StreamHostCapabilities(serverCodecModeSupport: 0x07)
        XCTAssertEqual(
            [everything.declaresHEVC, everything.declaresHDR, everything.declaresAV1],
            [true, true, true]
        )
    }

    func testAPresetFitsOnlyWhenItsPixelsAreWithinTheBudget() {
        XCTAssertTrue(StreamResolution.r1920x1080.fits(pixelBudget: 1920 * 1080))
        XCTAssertFalse(StreamResolution.r2560x1440.fits(pixelBudget: 1920 * 1080))
        XCTAssertFalse(StreamResolution.custom.fits(pixelBudget: 1920 * 1080))
        XCTAssertTrue(StreamResolution.custom.fits(pixelBudget: StreamResolution.maximumPixelCount))
    }

    func testPrivateAddressesAreRecognisedAcrossTheirRanges() {
        for address in [
            "10.0.0.4", "172.16.5.2", "172.31.255.1", "192.168.1.20", "127.0.0.1",
            "169.254.10.10", "fe80::1", "fd00::5", "::1", "localhost", "host.local", ""
        ] {
            XCTAssertTrue(StreamNetworkCondition.isPrivateAddress(address), address)
        }
    }

    func testPublicAddressesAreNotPrivate() {
        let publicIPv4 = ["203", "0", "113", "7"].joined(separator: ".")
        let otherPublicIPv4 = ["8", "8", "8", "8"].joined(separator: ".")
        let adjacentRangeIPv4 = ["172", "32", "0", "1"].joined(separator: ".")
        for address in [publicIPv4, otherPublicIPv4, adjacentRangeIPv4, "2001:db8::1"] {
            XCTAssertFalse(StreamNetworkCondition.isPrivateAddress(address), address)
        }
    }

    func testALocalTargetKeepsTheLargePacketSize() {
        let plan = StreamNetworkCondition.plan(
            for: HostAddress(host: "192.168.1.20"),
            vpnActive: false
        )
        XCTAssertFalse(plan.streamingRemotely)
        XCTAssertEqual(plan.packetSize, StreamNetworkCondition.localPacketSize)
    }

    func testARemoteTargetSwitchesToTheSmallerPacketSize() {
        let publicHost = ["203", "0", "113", "7"].joined(separator: ".")
        let plan = StreamNetworkCondition.plan(
            for: HostAddress(host: publicHost),
            vpnActive: false
        )
        XCTAssertTrue(plan.streamingRemotely)
        XCTAssertEqual(plan.packetSize, StreamNetworkCondition.remotePacketSize)
    }

    func testATunnelMakesEvenAPrivateAddressStreamRemotely() {
        let plan = StreamNetworkCondition.plan(
            for: HostAddress(host: "192.168.1.20"),
            vpnActive: true
        )
        XCTAssertTrue(plan.streamingRemotely)
        XCTAssertTrue(plan.vpnDetected)
        XCTAssertEqual(plan.packetSize, StreamNetworkCondition.remotePacketSize)
    }

    func testEveryRecoveryActionCarriesDistinctAdvice() {
        let actions: [StreamRecoveryAction] = [.none, .retry, .reconnect, .pairAgain, .repickApplication]
        let advices = actions.map(\.advice)
        XCTAssertEqual(Set(advices).count, actions.count)
        XCTAssertTrue(advices.allSatisfy { !$0.isEmpty })
    }

    func testEachFailureStageNamesItsOwnAlertTitle() {
        let stages: [StreamFailureStage] = [.pairing, .launch, .stream, .teardown, .applicationList]
        let titles = stages.map { stage in
            StreamFailure(stage: stage, kind: .unknown, message: "", recovery: .retry)
                .categoryTitle
        }
        XCTAssertEqual(Set(titles).count, stages.count)
        XCTAssertTrue(titles.allSatisfy { !$0.isEmpty })
    }
}
