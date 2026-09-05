import Foundation

public enum DebugProbeRetention: Equatable {
    case diagnostic
    case evidence
    case evidenceSession(String)
}

#if DEBUG
private enum DebugProbeRecordRetention: String {
    case diagnostic
    case evidence
}

private struct DebugProbeRecord {
    let sequence: UInt64
    let retention: DebugProbeRecordRetention
    let session: String?
    let line: String

    var byteCount: Int {
        line.utf8.count
    }
}

private struct LoadedDebugProbeState {
    let records: [DebugProbeRecord]
    let currentSession: String?
    let nextSequence: UInt64
    let byteCount: Int
}

@MainActor
public final class DebugProbeJournal {
    struct Configuration {
        let url: URL
        let byteLimit: Int
        let compactionTarget: Int
        let now: () -> Date
        let retainsLoadedEvidence: Bool

        init(
            url: URL,
            byteLimit: Int,
            compactionTarget: Int,
            now: @escaping () -> Date,
            retainsLoadedEvidence: Bool = true
        ) {
            self.url = url
            self.byteLimit = byteLimit
            self.compactionTarget = compactionTarget
            self.now = now
            self.retainsLoadedEvidence = retainsLoadedEvidence
        }

        static let product = Configuration(
            url: URL.documentsDirectory.appending(path: "surface-tap-probe.log"),
            byteLimit: 192 * 1_024,
            compactionTarget: 128 * 1_024,
            now: Date.init,
            retainsLoadedEvidence:
                ProcessInfo.processInfo.environment["ENCHRON_TEST_CHANNEL"] == "1"
        )
    }

    public struct Status: Equatable {
        public let byteLimit: Int
        public fileprivate(set) var fileBytes: Int
        public fileprivate(set) var peakFileBytes: Int
        public fileprivate(set) var compactionCount: Int
        public fileprivate(set) var evidenceOverflowed: Bool
        public fileprivate(set) var writeFailed: Bool
    }

    private let configuration: Configuration
    private var records: [DebugProbeRecord]
    private var currentSession: String?
    private var nextSequence: UInt64
    private(set) var status: Status

    init(configuration: Configuration) {
        precondition(configuration.byteLimit > 0)
        precondition(configuration.compactionTarget > 0)
        precondition(configuration.compactionTarget <= configuration.byteLimit)
        self.configuration = configuration

        let loaded = Self.loadRecords(
            from: configuration.url,
            retainsEvidence: configuration.retainsLoadedEvidence
        )
        records = loaded.records
        currentSession = loaded.currentSession
        nextSequence = loaded.nextSequence
        status = Status(
            byteLimit: configuration.byteLimit,
            fileBytes: loaded.byteCount,
            peakFileBytes: 0,
            compactionCount: 0,
            evidenceOverflowed: false,
            writeFailed: false
        )

        if loaded.byteCount > configuration.byteLimit {
            compactToTarget()
        }
        status.peakFileBytes = status.fileBytes
    }

    func record(_ fact: String, retention: DebugProbeRetention) {
        let session: String?
        let storedRetention: DebugProbeRecordRetention
        switch retention {
        case .diagnostic:
            session = currentSession
            storedRetention = .diagnostic
        case .evidence:
            session = currentSession
            storedRetention = .evidence
        case .evidenceSession(let sessionID):
            if currentSession != sessionID {
                records.removeAll(keepingCapacity: true)
                currentSession = sessionID
                rewriteFile()
            }
            session = sessionID
            storedRetention = .evidence
        }

        let record = makeRecord(
            fact: fact,
            retention: storedRetention,
            session: session
        )
        let projectedBytes = status.fileBytes + record.byteCount
        if projectedBytes <= configuration.byteLimit {
            records.append(record)
            append(record)
            return
        }

        if storedRetention == .evidence {
            let evidenceBytes = records
                .filter { $0.retention == .evidence }
                .reduce(record.byteCount) { $0 + $1.byteCount }
            guard evidenceBytes <= configuration.byteLimit else {
                status.evidenceOverflowed = true
                return
            }
        }

        records.append(record)
        compactToTarget()
    }

    private func makeRecord(
        fact: String,
        retention: DebugProbeRecordRetention,
        session: String?
    ) -> DebugProbeRecord {
        let sequence = nextSequence
        nextSequence &+= 1
        let singleLineFact = fact
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
        let sessionToken = session.map(Self.encodeSession) ?? "none"
        let line = configuration.now().ISO8601Format()
            + " probeSequence=\(sequence)"
            + " probeRetention=\(retention.rawValue)"
            + " probeSession=\(sessionToken)"
            + " \(singleLineFact)\n"
        return DebugProbeRecord(
            sequence: sequence,
            retention: retention,
            session: session,
            line: line
        )
    }

    private func append(_ record: DebugProbeRecord) {
        let data = Data(record.line.utf8)
        do {
            try FileManager.default.createDirectory(
                at: configuration.url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if FileManager.default.fileExists(atPath: configuration.url.path) {
                let handle = try FileHandle(forWritingTo: configuration.url)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
            } else {
                try data.write(to: configuration.url, options: .atomic)
            }
            status.fileBytes += data.count
            status.peakFileBytes = max(status.peakFileBytes, status.fileBytes)
        } catch {
            records.removeAll { $0.sequence == record.sequence }
            status.writeFailed = true
        }
    }

    private func compactToTarget() {
        let evidence = records.filter { $0.retention == .evidence }
        let evidenceBytes = evidence.reduce(0) { $0 + $1.byteCount }
        guard evidenceBytes <= configuration.byteLimit else {
            records.removeAll(keepingCapacity: true)
            status.evidenceOverflowed = true
            rewriteFile()
            return
        }

        let target = max(configuration.compactionTarget, evidenceBytes)
        var selectedSequences = Set(evidence.map(\.sequence))
        var selectedBytes = evidenceBytes
        for record in records.reversed() where record.retention == .diagnostic {
            guard selectedBytes + record.byteCount <= target else { continue }
            selectedSequences.insert(record.sequence)
            selectedBytes += record.byteCount
        }
        records = records.filter { selectedSequences.contains($0.sequence) }
        status.compactionCount += 1
        rewriteFile()
    }

    private func rewriteFile() {
        let data = Data(records.flatMap { $0.line.utf8 })
        guard data.count <= configuration.byteLimit else {
            status.evidenceOverflowed = true
            return
        }
        do {
            try FileManager.default.createDirectory(
                at: configuration.url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: configuration.url, options: .atomic)
            status.fileBytes = data.count
            status.peakFileBytes = max(status.peakFileBytes, data.count)
        } catch {
            status.writeFailed = true
        }
    }

    private static func loadRecords(
        from url: URL,
        retainsEvidence: Bool
    ) -> LoadedDebugProbeState {
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else {
            return LoadedDebugProbeState(
                records: [],
                currentSession: nil,
                nextSequence: 0,
                byteCount: 0
            )
        }
        var nextLegacySequence: UInt64 = 0
        var parsed: [DebugProbeRecord] = []
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = String(rawLine) + "\n"
            let tokens = rawLine.split(separator: " ")
            let sequence = tokens
                .first { $0.hasPrefix("probeSequence=") }
                .flatMap { UInt64($0.dropFirst("probeSequence=".count)) }
                ?? nextLegacySequence
            nextLegacySequence = max(nextLegacySequence, sequence &+ 1)
            let storedRetention = tokens
                .first { $0.hasPrefix("probeRetention=") }
                .flatMap {
                    DebugProbeRecordRetention(
                        rawValue: String($0.dropFirst("probeRetention=".count))
                    )
                }
                ?? .diagnostic
            let session = tokens
                .first { $0.hasPrefix("probeSession=") }
                .map { String($0.dropFirst("probeSession=".count)) }
                .flatMap(decodeSession)
            if retainsEvidence {
                parsed.append(
                    DebugProbeRecord(
                        sequence: sequence,
                        retention: storedRetention,
                        session: session,
                        line: line
                    )
                )
            } else {
                parsed.append(
                    DebugProbeRecord(
                        sequence: sequence,
                        retention: .diagnostic,
                        session: nil,
                        line: line.replacingOccurrences(
                            of: " probeRetention=evidence ",
                            with: " probeRetention=diagnostic "
                        )
                    )
                )
            }
        }
        return LoadedDebugProbeState(
            records: parsed,
            currentSession: retainsEvidence
                ? parsed.reversed().compactMap(\.session).first
                : nil,
            nextSequence: nextLegacySequence,
            byteCount: data.count
        )
    }

    private static func encodeSession(_ session: String) -> String {
        Data(session.utf8).base64EncodedString()
    }

    private static func decodeSession(_ token: String) -> String? {
        guard token != "none",
              let data = Data(base64Encoded: token) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
}
#endif
