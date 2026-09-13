/// Runtime-selectable simulation strategies for the FFT ocean probe.
///
/// `throttled` keeps the historical behaviour: simulation ticks are capped at
/// 45 Hz, cascade detail alternates between 2-cascade and 4-cascade updates,
/// and every render frame blends the two most recent simulation snapshots.
///
/// `fullRate` offers a simulation tick every render frame and alternates the
/// updated cascade pair {0,1} / {2,3}, so every frame lands a real simulation
/// result for half the cascades instead of an interpolated approximation.
/// Spectrum evolution is evaluated from absolute time, so a skipped cascade
/// resumes with an exact phase advance — no interpolation error is introduced.
public enum OceanSimulationMode: String, Sendable {
    case throttled
    case fullRate
}

/// Process-wide switches read by `OceanProbeSystem` once per update.
@MainActor
public enum OceanSimulationControl {
    public static var mode: OceanSimulationMode = .throttled

    /// When false the ocean surface entity stays hidden while simulation and
    /// presentation keep running, so fragment/compositing cost can be measured
    /// against an identical compute workload.
    public static var surfaceEnabled = true
}
