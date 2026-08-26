import OSLog

public enum SurfaceInputProbes {
    public static func record(
        _ fact: String,
        retention: DebugProbeRetention = .diagnostic
    ) {
#if DEBUG
        Logger(subsystem: "app.enchron", category: "Presentation")
            .notice("surface input probe \(fact, privacy: .public)")
        journal.record(fact, retention: retention)
#endif
    }

#if DEBUG
    public static var status: DebugProbeJournal.Status {
        journal.status
    }

    private static let journal = DebugProbeJournal(
        configuration: .product
    )
#endif
}
