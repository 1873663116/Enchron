import GameStreaming
import XCTest

nonisolated final class StreamAddressPlanTests: XCTestCase {
    private let local = HostAddress(host: "192.168.1.20")
    private let primary = HostAddress(host: "10.0.0.20")
    private let alternate = HostAddress(host: "enchron-host.local")
    private let external = HostAddress(host: "203.0.113.7")

    func testLocalAddressIsTriedBeforeTheStoredOne() {
        let plan = StreamAddressPlan.candidates(
            primary: primary,
            local: local,
            alternates: nil,
            external: nil
        )
        XCTAssertEqual(plan, [local, primary])
    }

    func testAlternatesSitBetweenTheLocalPathAndTheWanPath() {
        let plan = StreamAddressPlan.candidates(
            primary: primary,
            local: local,
            alternates: [alternate],
            external: external
        )
        XCTAssertEqual(plan, [local, primary, alternate, external])
    }

    func testRepeatedAddressesCollapseToTheFirstAppearance() {
        let plan = StreamAddressPlan.candidates(
            primary: local,
            local: local,
            alternates: [primary, local],
            external: primary
        )
        XCTAssertEqual(plan, [local, primary])
    }

    func testAMagicPacketIsSixFFBytesThenTheAddressSixteenTimes() {
        let packet = StreamWakeOnLan.magicPacket(mac: "AA:BB:CC:DD:EE:FF")
        XCTAssertEqual(packet?.count, 102)
        let bytes = [UInt8](packet ?? Data())
        XCTAssertEqual(Array(bytes.prefix(6)), [0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF])
        let macBytes: [UInt8] = [0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF]
        for repeatIndex in 0..<16 {
            let start = 6 + repeatIndex * 6
            XCTAssertEqual(Array(bytes[start..<(start + 6)]), macBytes)
        }
    }

    func testDashSeparatedAndLowerCaseAddressesAreAccepted() {
        XCTAssertEqual(
            StreamWakeOnLan.magicPacket(mac: "aa-bb-cc-dd-ee-ff"),
            StreamWakeOnLan.magicPacket(mac: "AA:BB:CC:DD:EE:FF")
        )
    }

    func testMalformedAddressesProduceNoPacket() {
        XCTAssertNil(StreamWakeOnLan.magicPacket(mac: ""))
        XCTAssertNil(StreamWakeOnLan.magicPacket(mac: "AA:BB:CC"))
        XCTAssertNil(StreamWakeOnLan.magicPacket(mac: "ZZ:BB:CC:DD:EE:FF"))
    }
}
