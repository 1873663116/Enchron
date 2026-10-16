import Foundation
import Playback

public enum StreamSessionProbes {
    public static func record(
        _ fact: @autoclosure () -> String,
        retention: DebugProbeRetention = .diagnostic
    ) {
#if DEBUG
        let fact = fact()
        Task { @MainActor in
            journal.record(fact, retention: retention)
        }
#endif
    }

#if DEBUG
    @MainActor
    public static var status: DebugProbeJournal.Status {
        journal.status
    }

    @MainActor
    private static let journal = DebugProbeJournal(
        configuration: DebugProbeJournal.Configuration(
            url: URL.documentsDirectory.appending(path: "stream-session-probe.log"),
            byteLimit: 192 * 1_024,
            compactionTarget: 128 * 1_024,
            now: Date.init,
            retainsLoadedEvidence:
                ProcessInfo.processInfo.environment["ENCHRON_TEST_CHANNEL"] == "1"
        )
    )
#endif
}
