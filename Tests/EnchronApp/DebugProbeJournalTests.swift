import Foundation
import XCTest
@testable import Enchron
@testable import Playback

#if DEBUG
nonisolated final class DebugProbeJournalTests: XCTestCase {
    @MainActor
    func testWindowSettlementSignatureIgnoresOnlyFastChangingFields() {
        let first = [
            "settled=false",
            "rendererStatus=rendering",
            "synchronizerTime=1.0",
            "lastVideoPTS=1.0",
            "acceptedRendererInputCount=10"
        ]
        let laterFrame = [
            "settled=false",
            "rendererStatus=rendering",
            "synchronizerTime=2.0",
            "lastVideoPTS=2.0",
            "acceptedRendererInputCount=20"
        ]
        let stateChange = [
            "settled=true",
            "rendererStatus=rendering",
            "synchronizerTime=2.0",
            "lastVideoPTS=2.0",
            "acceptedRendererInputCount=20"
        ]

        XCTAssertEqual(
            PlaybackSettlementProbeSignature.make(fields: first),
            PlaybackSettlementProbeSignature.make(fields: laterFrame)
        )
        XCTAssertNotEqual(
            PlaybackSettlementProbeSignature.make(fields: first),
            PlaybackSettlementProbeSignature.make(fields: stateChange)
        )
    }

    @MainActor
    func testDiagnosticPressureNeverCrossesTheByteLimit() throws {
        let fixture = try ProbeJournalFixture(byteLimit: 4_096, compactionTarget: 2_048)
        defer { fixture.remove() }
        let journal = DebugProbeJournal(configuration: fixture.configuration)

        journal.record(
            "reachability evidence session=bounded-session command=first verb=resetState",
            retention: .evidenceSession("bounded-session")
        )
        journal.record(
            "reachability files delivered action=remote.folder",
            retention: .evidence
        )

        for index in 0..<10_000 {
            journal.record(
                "windowSettlement index=\(index),payload=\(String(repeating: "x", count: 384))",
                retention: .diagnostic
            )
            XCTAssertLessThanOrEqual(try fixture.fileBytes(), 4_096)
        }

        let status = journal.status
        XCTAssertLessThanOrEqual(status.fileBytes, 4_096)
        XCTAssertLessThanOrEqual(status.peakFileBytes, 4_096)
        XCTAssertGreaterThan(status.compactionCount, 0)
        XCTAssertFalse(status.evidenceOverflowed)
    }

    @MainActor
    func testCompactionAndReloadPreserveEvidenceFactsAndOrder() throws {
        let fixture = try ProbeJournalFixture(byteLimit: 4_096, compactionTarget: 2_048)
        defer { fixture.remove() }
        let firstJournal = DebugProbeJournal(configuration: fixture.configuration)
        let requiredFacts = [
            "reachability evidence session=replay-session command=1 verb=resetState",
            "navigation tab delivered tab=files",
            "reachability files delivered action=remote.folder",
            "testcmd selectMenuItem ok",
            "setWindowSize observed=1280x720",
            "worldLoad event=completed anchor=PlaybackSurfaceAnchor"
        ]

        firstJournal.record(requiredFacts[0], retention: .evidenceSession("replay-session"))
        for fact in requiredFacts.dropFirst().prefix(2) {
            firstJournal.record(fact, retention: .evidence)
        }
        for index in 0..<1_000 {
            firstJournal.record(
                "windowSettlement beforeReload=\(index),payload=\(String(repeating: "y", count: 256))",
                retention: .diagnostic
            )
        }

        let reloadedJournal = DebugProbeJournal(configuration: fixture.configuration)
        for fact in requiredFacts.dropFirst(3) {
            reloadedJournal.record(fact, retention: .evidence)
        }
        for index in 0..<1_000 {
            reloadedJournal.record(
                "windowSettlement afterReload=\(index),payload=\(String(repeating: "z", count: 256))",
                retention: .diagnostic
            )
        }

        let lines = try fixture.lines()
        let durableLines = lines.filter { $0.contains("probeRetention=evidence") }
        XCTAssertEqual(durableLines.count, requiredFacts.count)
        for (line, fact) in zip(durableLines, requiredFacts) {
            XCTAssertTrue(line.contains(fact), "Missing durable fact: \(fact)")
            XCTAssertNotNil(ISO8601DateFormatter().date(from: String(line.split(separator: " ")[0])))
        }
        let sequences = try durableLines.map(Self.sequence)
        XCTAssertEqual(sequences, sequences.sorted())
        XCTAssertEqual(Set(sequences).count, sequences.count)
        XCTAssertLessThanOrEqual(try fixture.fileBytes(), 4_096)
        XCTAssertFalse(reloadedJournal.status.evidenceOverflowed)
    }

    @MainActor
    func testNewEvidenceSessionAtomicallyReplacesThePreviousSession() throws {
        let fixture = try ProbeJournalFixture(byteLimit: 4_096, compactionTarget: 2_048)
        defer { fixture.remove() }
        let journal = DebugProbeJournal(configuration: fixture.configuration)

        journal.record(
            "reachability evidence session=old command=1 verb=resetState",
            retention: .evidenceSession("old")
        )
        journal.record("reachability files delivered action=library.folder", retention: .evidence)
        journal.record(
            "reachability evidence session=new command=2 verb=resetState",
            retention: .evidenceSession("new")
        )

        let text = try fixture.text()
        XCTAssertFalse(text.contains("session=old"))
        XCTAssertFalse(text.contains("action=library.folder"))
        XCTAssertTrue(text.contains("session=new"))
    }

    @MainActor
    func testLaunchWithoutTestChannelDemotesLoadedEvidence() throws {
        let fixture = try ProbeJournalFixture(byteLimit: 4_096, compactionTarget: 2_048)
        defer { fixture.remove() }
        let harnessJournal = DebugProbeJournal(configuration: fixture.configuration)
        harnessJournal.record(
            "reachability evidence session=stale command=1 verb=resetState",
            retention: .evidenceSession("stale")
        )
        for index in 0..<40 {
            harnessJournal.record(
                "reachability fileScroll index=\(index)"
                    + String(repeating: "s", count: 64),
                retention: .evidence
            )
        }
        XCTAssertGreaterThan(try fixture.fileBytes(), 2_048)

        let manualJournal = DebugProbeJournal(
            configuration: fixture.manualLaunchConfiguration
        )
        manualJournal.record(
            "playbackWindowHandover pushed incoming=playback outgoing=main",
            retention: .evidence
        )
        for index in 0..<200 {
            manualJournal.record(
                "windowSettlement manual=\(index)" + String(repeating: "m", count: 128),
                retention: .diagnostic
            )
        }

        let text = try fixture.text()
        XCTAssertTrue(text.contains("playbackWindowHandover pushed incoming=playback"))
        XCTAssertTrue(text.contains("windowSettlement manual=199"))
        XCTAssertFalse(text.contains("session=stale"))
        XCTAssertLessThanOrEqual(try fixture.fileBytes(), 4_096)
        XCTAssertFalse(manualJournal.status.evidenceOverflowed)
        let durable = try fixture.lines().filter { $0.contains("probeRetention=evidence") }
        XCTAssertEqual(durable.count, 1)
        XCTAssertTrue(durable[0].contains("probeSession=none"))
    }

    @MainActor
    func testEvidenceOverflowFailsClosedWithoutCrossingTheLimit() throws {
        let fixture = try ProbeJournalFixture(byteLimit: 512, compactionTarget: 256)
        defer { fixture.remove() }
        let journal = DebugProbeJournal(configuration: fixture.configuration)

        journal.record(
            "reachability evidence session=overflow command=1 verb=resetState",
            retention: .evidenceSession("overflow")
        )
        journal.record(String(repeating: "e", count: 2_048), retention: .evidence)

        XCTAssertTrue(journal.status.evidenceOverflowed)
        XCTAssertLessThanOrEqual(try fixture.fileBytes(), 512)
        XCTAssertFalse(try fixture.text().contains(String(repeating: "e", count: 2_048)))
    }

    private static func sequence(from line: String) throws -> UInt64 {
        let token = try XCTUnwrap(
            line.split(separator: " ").first { $0.hasPrefix("probeSequence=") }
        )
        return try XCTUnwrap(UInt64(token.dropFirst("probeSequence=".count)))
    }
}

@MainActor
private final class ProbeJournalFixture {
    let directory: URL
    let file: URL
    let configuration: DebugProbeJournal.Configuration

    init(byteLimit: Int, compactionTarget: Int) throws {
        directory = FileManager.default.temporaryDirectory
            .appending(path: "DebugProbeJournalTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        file = directory.appending(path: "surface-tap-probe.log")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var tick: TimeInterval = 0
        configuration = DebugProbeJournal.Configuration(
            url: file,
            byteLimit: byteLimit,
            compactionTarget: compactionTarget,
            now: {
                defer { tick += 0.001 }
                return Date(timeIntervalSince1970: 1_787_094_000 + tick)
            }
        )
    }

    var manualLaunchConfiguration: DebugProbeJournal.Configuration {
        DebugProbeJournal.Configuration(
            url: configuration.url,
            byteLimit: configuration.byteLimit,
            compactionTarget: configuration.compactionTarget,
            now: configuration.now,
            retainsLoadedEvidence: false
        )
    }

    func fileBytes() throws -> Int {
        try Data(contentsOf: file).count
    }

    func lines() throws -> [String] {
        try text().split(separator: "\n").map(String.init)
    }

    func text() throws -> String {
        try String(contentsOf: file, encoding: .utf8)
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }
}
#endif
