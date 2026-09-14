import DesignSystem
import PlaybackCore
import SwiftUI

struct DeveloperStatsField: Identifiable {
    let key: String
    let value: String
    var unit: String?
    var denominator: String?
    var suffix: String?

    var id: String { key }
}

struct DeveloperStatsGroup: Identifiable {
    let id: String
    let fields: [DeveloperStatsField]
}

public enum DeveloperStatsLine {
    static func groups(
        metrics: DeveloperProcessMetrics,
        sceneUpdatesPerSecond: Double?,
        enqueuedSamplesPerSecond: Double?,
        playback: PlaybackDiagnostics?,
        sessionIsActive: Bool
    ) -> [DeveloperStatsGroup] {
        var result: [DeveloperStatsGroup] = []

        var memory: [DeveloperStatsField] = [
            DeveloperStatsField(
                key: "MEM",
                value: megabytes(metrics.footprintBytes),
                unit: "MB",
                denominator: metrics.limitIsReported ? megabytes(metrics.limitBytes) : nil
            ),
            DeveloperStatsField(
                key: "INT",
                value: megabytes(metrics.internalBytes),
                unit: "MB"
            )
        ]
        if let graphics = metrics.graphicsFootprintBytes {
            memory.append(
                DeveloperStatsField(
                    key: "GFX",
                    value: megabytes(UInt64(max(graphics, 0))),
                    unit: "MB"
                )
            )
        }
        for (key, bytes) in [
            ("IOSF", metrics.ioSurfaceResidentBytes),
            ("IOAC", metrics.ioAcceleratorResidentBytes),
            ("CM", metrics.coreMediaResidentBytes),
            ("VBS", metrics.videoBitstreamResidentBytes)
        ] as [(String, UInt64?)] {
            if let bytes, bytes > 0 {
                memory.append(
                    DeveloperStatsField(key: key, value: megabytes(bytes), unit: "MB")
                )
            }
        }
        result.append(DeveloperStatsGroup(id: "memory", fields: memory))

        var cadence: [DeveloperStatsField] = []
        if let sceneUpdatesPerSecond {
            cadence.append(
                DeveloperStatsField(
                    key: "SCENE",
                    value: String(Int(sceneUpdatesPerSecond.rounded())),
                    unit: "Hz",
                    denominator: metrics.refreshHz.map { String(Int($0.rounded())) }
                )
            )
        }
        cadence.append(stallField(metrics))
        result.append(DeveloperStatsGroup(id: "cadence", fields: cadence))

        if sessionIsActive, let playback {
            var session: [DeveloperStatsField] = []
            if let lead = playback.videoLeadFramesBudget {
                session.append(
                    DeveloperStatsField(
                        key: "LEAD",
                        value: String(lead),
                        denominator: playback.videoLeadFramesCeiling.map(String.init)
                    )
                )
            }
            if let buffer = playback.demuxBuffer, buffer.forwardLimitBytes > 0 {
                session.append(
                    DeveloperStatsField(
                        key: "DEMUX",
                        value: megabytes(UInt64(max(buffer.forwardBufferedBytes, 0))),
                        unit: "MB",
                        denominator: megabytes(UInt64(max(buffer.forwardLimitBytes, 0)))
                    )
                )
            }
            if playback.nominalFrameRate > 0 {
                session.append(
                    DeveloperStatsField(
                        key: "ENQ",
                        value: enqueuedSamplesPerSecond.map { String(Int($0.rounded())) } ?? "?",
                        unit: "/s",
                        denominator: String(format: "%.3f", playback.nominalFrameRate)
                    )
                )
            }
            if session.isEmpty == false {
                result.append(DeveloperStatsGroup(id: "session", fields: session))
            }
        }

        return result
    }

    public static func text(
        metrics: DeveloperProcessMetrics,
        sceneUpdatesPerSecond: Double?,
        enqueuedSamplesPerSecond: Double?,
        playback: PlaybackDiagnostics?,
        sessionIsActive: Bool
    ) -> String {
        groups(
            metrics: metrics,
            sceneUpdatesPerSecond: sceneUpdatesPerSecond,
            enqueuedSamplesPerSecond: enqueuedSamplesPerSecond,
            playback: playback,
            sessionIsActive: sessionIsActive
        )
        .map { group in
            group.fields.map { field in
                var text = "\(field.key) \(field.value)"
                if let denominator = field.denominator { text += "/\(denominator)" }
                if let unit = field.unit { text += unit }
                if let suffix = field.suffix { text += " \(suffix)" }
                return text
            }
            .joined(separator: " ")
        }
        .joined(separator: " · ")
    }

    private static func stallField(_ metrics: DeveloperProcessMetrics) -> DeveloperStatsField {
        guard metrics.missedBeatCount > 0 else {
            return DeveloperStatsField(key: "STALL", value: "0")
        }
        return DeveloperStatsField(
            key: "STALL",
            value: String(Int((metrics.longestStallSeconds * 1000).rounded())),
            unit: "ms",
            suffix: "×\(metrics.missedBeatCount)"
        )
    }

    private static func megabytes(_ bytes: UInt64) -> String {
        String(bytes / 1_048_576)
    }
}

public struct DeveloperStatsOverlay: View {
    private let metrics: DeveloperProcessMetrics
    private let sceneUpdatesPerSecond: Double?
    private let enqueuedSamplesPerSecond: Double?
    private let playback: PlaybackDiagnostics?
    private let sessionIsActive: Bool

    public init(
        metrics: DeveloperProcessMetrics,
        sceneUpdatesPerSecond: Double? = nil,
        enqueuedSamplesPerSecond: Double? = nil,
        playback: PlaybackDiagnostics? = nil,
        sessionIsActive: Bool = false
    ) {
        self.metrics = metrics
        self.sceneUpdatesPerSecond = sceneUpdatesPerSecond
        self.enqueuedSamplesPerSecond = enqueuedSamplesPerSecond
        self.playback = playback
        self.sessionIsActive = sessionIsActive
    }

    private var groups: [DeveloperStatsGroup] {
        DeveloperStatsLine.groups(
            metrics: metrics,
            sceneUpdatesPerSecond: sceneUpdatesPerSecond,
            enqueuedSamplesPerSecond: enqueuedSamplesPerSecond,
            playback: playback,
            sessionIsActive: sessionIsActive
        )
    }

    public var body: some View {
        HStack(spacing: DesignTokens.Spacing.xxs) {
            ForEach(groups) { group in
                HStack(spacing: DesignTokens.Spacing.xs) {
                    ForEach(group.fields) { field in
                        reading(field)
                    }
                }
                .padding(.horizontal, DesignTokens.Spacing.xs)
                .padding(.vertical, DesignTokens.Spacing.xxs)
                .background(
                    DesignTokens.Surface.textScrimMaterial,
                    in: .rect(cornerRadius: DesignTokens.Radius.small)
                )
            }
        }
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("DeveloperStatsOverlay")
        .accessibilityLabel(
            DeveloperStatsLine.text(
                metrics: metrics,
                sceneUpdatesPerSecond: sceneUpdatesPerSecond,
                enqueuedSamplesPerSecond: enqueuedSamplesPerSecond,
                playback: playback,
                sessionIsActive: sessionIsActive
            )
        )
        .allowsHitTesting(false)
    }

    private func reading(_ field: DeveloperStatsField) -> some View {
        HStack(spacing: DesignTokens.Spacing.xxs) {
            Text(field.key)
                .font(DesignTokens.Typography.sectionHeader)
                .foregroundStyle(DesignTokens.Surface.supportingText)
            HStack(spacing: 0) {
                Text(field.value)
                if let denominator = field.denominator {
                    Text("/\(denominator)")
                        .foregroundStyle(DesignTokens.Surface.supportingText)
                }
                if let unit = field.unit {
                    Text(unit)
                        .font(DesignTokens.Typography.sectionHeader)
                        .foregroundStyle(DesignTokens.Surface.supportingText)
                }
                if let suffix = field.suffix {
                    Text(" \(suffix)")
                        .foregroundStyle(DesignTokens.Surface.supportingText)
                }
            }
            .font(DesignTokens.Typography.monospacedDetail)
            .monospacedDigit()
        }
    }
}

public struct DeveloperStatsOverlayReader: View {
    @Environment(DeveloperMetricsModel.self) private var developerMetrics
    @Environment(PlaybackRuntime.self) private var playbackRuntime
    private let sceneKey: DeveloperMetricsModel.SceneKey?
    private let includePlayback: Bool

    public init(
        sceneKey: DeveloperMetricsModel.SceneKey? = nil,
        includePlayback: Bool = true
    ) {
        self.sceneKey = sceneKey
        self.includePlayback = includePlayback
    }

    public var body: some View {
        DeveloperStatsOverlay(
            metrics: developerMetrics.metrics,
            sceneUpdatesPerSecond: sceneKey.flatMap {
                developerMetrics.sceneUpdatesPerSecond[$0]
            },
            enqueuedSamplesPerSecond: developerMetrics.enqueuedSamplesPerSecond,
            playback: includePlayback ? playbackRuntime.diagnostics : nil,
            sessionIsActive: includePlayback
                && playbackRuntime.activeSessionID != nil
        )
    }
}

public extension View {
    func developerStatsOverlay(
        isEnabled: Bool,
        sceneKey: DeveloperMetricsModel.SceneKey? = nil,
        includePlayback: Bool = true
    ) -> some View {
        overlay(alignment: .bottomTrailing) {
            if isEnabled {
                DeveloperStatsOverlayReader(
                    sceneKey: sceneKey,
                    includePlayback: includePlayback
                )
                .enchronSpatialFrame(depth: 0)
                .enchronSpatialOffset(
                    z: WindowPlaybackSurfaceGeometry.coincidentChromeDepth
                )
                .padding(DesignTokens.Spacing.sm)
            }
        }
    }

    func developerStatsOverlay(
        isEnabled: Bool,
        metrics: DeveloperProcessMetrics,
        sceneUpdatesPerSecond: Double? = nil,
        enqueuedSamplesPerSecond: Double? = nil,
        playback: PlaybackDiagnostics? = nil,
        sessionIsActive: Bool = false
    ) -> some View {
        overlay(alignment: .bottomTrailing) {
            if isEnabled {
                DeveloperStatsOverlay(
                    metrics: metrics,
                    sceneUpdatesPerSecond: sceneUpdatesPerSecond,
                    enqueuedSamplesPerSecond: enqueuedSamplesPerSecond,
                    playback: playback,
                    sessionIsActive: sessionIsActive
                )
                .enchronSpatialFrame(depth: 0)
                .enchronSpatialOffset(z: WindowPlaybackSurfaceGeometry.coincidentChromeDepth)
                .padding(DesignTokens.Spacing.sm)
            }
        }
    }
}
