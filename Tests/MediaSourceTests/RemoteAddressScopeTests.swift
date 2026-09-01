import Foundation
import MediaSource
import Testing

struct RemoteAddressScopeTests {
    @Test(
        "each address form lands in the scope that decides whether cleartext stays off the internet",
        arguments: [
            ("127.0.0.1", RemoteAddressScope.loopback),
            ("127.255.255.254", .loopback),
            ("128.0.0.1", .publicAddress),
            ("126.255.255.255", .publicAddress),
            ("fe80::1%en0", .linkLocal),
            ("febf::1", .linkLocal),
            ("fec0::1", .publicAddress),
            ("::1", .loopback),
            ("10.0.0.0", .privateNetwork),
            ("10.255.255.255", .privateNetwork),
            ("172.15.255.255", .publicAddress),
            ("172.16.0.0", .privateNetwork),
            ("172.31.255.255", .privateNetwork),
            ("172.32.0.0", .publicAddress),
            ("192.167.255.255", .publicAddress),
            ("192.168.0.0", .privateNetwork),
            ("192.168.5.28", .privateNetwork),
            ("192.169.0.0", .publicAddress),
            ("169.254.0.1", .linkLocal),
            ("fe80::1", .linkLocal),
            ("100.63.255.255", .publicAddress),
            ("100.64.0.0", .carrierGradeNAT),
            ("100.108.103.46", .carrierGradeNAT),
            ("100.127.255.255", .carrierGradeNAT),
            ("100.128.0.0", .publicAddress),
            ("fd7a:115c:a1e0::7301:67a9", .privateNetwork),
            ("fc00::1", .privateNetwork),
            ("fdff::1", .privateNetwork),
            ("fe00::1", .publicAddress),
            ("2001:db8::1", .publicAddress),
            ("[fd7a:115c:a1e0::7301:67a9]", .privateNetwork),
            ("::ffff:192.168.5.28", .privateNetwork),
            ("::ffff:45.78.51.92", .publicAddress),
            ("45.78.51.92", .publicAddress),
            ("8.8.8.8", .publicAddress),
            ("mac-mini.local", .multicastDNSName),
            ("Mac-mini.LOCAL", .multicastDNSName),
            ("mac-mini", .unqualifiedName),
            ("mac-mini.tailbbeec7.ts.net", .qualifiedName),
            ("myserver.duckdns.org", .qualifiedName)
        ]
    )
    func scopeOfHost(host: String, expected: RemoteAddressScope) {
        #expect(RemoteAddressScope(host: host) == expected)
    }

    @Test(
        "only public addresses and qualified names let cleartext reach the internet",
        arguments: [
            (RemoteAddressScope.loopback, true),
            (.privateNetwork, true),
            (.linkLocal, true),
            (.carrierGradeNAT, true),
            (.multicastDNSName, true),
            (.unqualifiedName, true),
            (.publicAddress, false),
            (.qualifiedName, false)
        ]
    )
    func containment(scope: RemoteAddressScope, keepsCleartextOff: Bool) {
        #expect(scope.keepsCleartextOffThePublicInternet == keepsCleartextOff)
    }
}

struct CleartextExposurePolicyTests {
    @Test(
        "the decision covers scheme, address scope and a remembered acknowledgement",
        arguments: [
            ("http://192.168.5.28:8096", CleartextExposureDecision.proceed),
            ("http://100.108.103.46:8096", .proceed),
            ("http://mac-mini.local:8096", .proceed),
            ("https://45.78.51.92:8096", .proceed),
            ("HTTPS://45.78.51.92:8096", .proceed),
            ("http://45.78.51.92:8096", .askBeforeSending(host: "45.78.51.92")),
            ("HTTP://45.78.51.92:8096", .askBeforeSending(host: "45.78.51.92")),
            ("http://myserver.duckdns.org", .askBeforeSending(host: "myserver.duckdns.org"))
        ]
    )
    func decision(address: String, expected: CleartextExposureDecision) throws {
        let policy = CleartextExposurePolicy(defaults: try emptyDefaults())
        #expect(policy.decision(for: try #require(URL(string: address))) == expected)
    }

    @Test("an acknowledged host stops being asked about, on any port")
    func acknowledgementSilencesTheHost() throws {
        let policy = CleartextExposurePolicy(defaults: try emptyDefaults())
        let asked = try #require(URL(string: "http://45.78.51.92:8096"))
        let otherPort = try #require(URL(string: "http://45.78.51.92:8920"))

        #expect(policy.decision(for: asked) == .askBeforeSending(host: "45.78.51.92"))
        policy.acknowledge(host: "45.78.51.92")

        #expect(policy.decision(for: asked) == .proceed)
        #expect(policy.decision(for: otherPort) == .proceed)
    }

    @Test("approving through the handler acknowledges the host exactly once")
    func approvalRemembers() async throws {
        let policy = CleartextExposurePolicy(defaults: try emptyDefaults())
        let counter = ApprovalCounter(answer: true)
        policy.approvalHandler = { host in await counter.approve(host) }
        let url = try #require(URL(string: "http://45.78.51.92:8096"))

        #expect(await policy.authorize(url))
        #expect(await policy.authorize(url))
        #expect(await counter.hosts == ["45.78.51.92"])
    }

    @Test("declining leaves the host unacknowledged so the next attempt asks again")
    func declineIsNotRemembered() async throws {
        let policy = CleartextExposurePolicy(defaults: try emptyDefaults())
        let counter = ApprovalCounter(answer: false)
        policy.approvalHandler = { host in await counter.approve(host) }
        let url = try #require(URL(string: "http://45.78.51.92:8096"))

        #expect(await policy.authorize(url) == false)
        #expect(await policy.authorize(url) == false)
        #expect(await counter.hosts == ["45.78.51.92", "45.78.51.92"])
    }

    @Test("an unwired prompt withholds the warning rather than the connection")
    func missingHandlerProceeds() async throws {
        let policy = CleartextExposurePolicy(defaults: try emptyDefaults())
        let exposed = try #require(URL(string: "http://45.78.51.92:8096"))
        let contained = try #require(URL(string: "http://192.168.5.28:8096"))

        #expect(await policy.authorize(exposed))
        #expect(await policy.authorize(contained))
        #expect(policy.decision(for: exposed) == .askBeforeSending(host: "45.78.51.92"))
    }

    private func emptyDefaults() throws -> UserDefaults {
        let suite = "cleartext-exposure-policy-tests.\(UUID().uuidString)"
        return try #require(UserDefaults(suiteName: suite))
    }
}

private actor ApprovalCounter {
    private(set) var hosts: [String] = []
    private let answer: Bool

    init(answer: Bool) {
        self.answer = answer
    }

    func approve(_ host: String) -> Bool {
        hosts.append(host)
        return answer
    }
}
