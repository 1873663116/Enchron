#if DEBUG
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
        sessionIsActive: Bool,
        requestedRefreshHz: Float? = nil,
        requestStatus: String = "Not requested",
        showsDetails: Bool = false
    ) -> [DeveloperStatsGroup] {
        var result: [DeveloperStatsGroup] = []

        var memory: [DeveloperStatsField] = [
            DeveloperStatsField(
                key: "Memory",
                value: megabytes(metrics.footprintBytes),
                unit: "MB",
                denominator: metrics.limitIsReported ? megabytes(metrics.limitBytes) : nil
            ),
            DeveloperStatsField(
                key: "Internal",
                value: megabytes(metrics.internalBytes),
                unit: "MB"
            )
        ]
        if let graphics = metrics.graphicsFootprintBytes {
            memory.append(
                DeveloperStatsField(
                    key: "Graphics",
                    value: megabytes(UInt64(max(graphics, 0))),
                    unit: "MB"
                )
            )
        }
        for (key, bytes) in [
            ("IOSurface", metrics.ioSurfaceResidentBytes),
            ("GPU buffers", metrics.ioAcceleratorResidentBytes),
            ("CoreMedia", metrics.coreMediaResidentBytes),
            ("Bitstream", metrics.videoBitstreamResidentBytes)
        ] as [(String, UInt64?)] {
            if let bytes, bytes > 0 {
                memory.append(
                    DeveloperStatsField(key: key, value: megabytes(bytes), unit: "MB")
                )
            }
        }
        let memoryDetails = Array(memory.dropFirst())
        memory = [memory[0]]

        var cadence: [DeveloperStatsField] = [
            DeveloperStatsField(
                key: "Video",
                value: playback.flatMap { $0.nominalFrameRate > 0 ? String(format: "%.3f", $0.nominalFrameRate) : nil } ?? "—",
                unit: "fps"
            )
        ]
        if let sceneUpdatesPerSecond {
            memory.append(
                DeveloperStatsField(
                    key: "Scene updates",
                    value: String(Int(sceneUpdatesPerSecond.rounded())),
                    unit: "Hz"
                )
            )
        }
        cadence.append(DeveloperStatsField(
            key: "Requested",
            value: requestedRefreshHz.map { String(format: "%.0f", $0) } ?? requestStatus,
            unit: requestedRefreshHz == nil ? nil : "Hz"
        ))
        cadence.append(DeveloperStatsField(
            key: "DisplayLink",
            value: metrics.refreshHz.map { String(format: "%.3f", $0) } ?? "—",
            unit: "Hz",
            suffix: "(app updates)"
        ))
        memory.append(stallField(metrics))
        result.append(DeveloperStatsGroup(id: "cadence", fields: cadence))

        if sessionIsActive, let playback {
            var session: [DeveloperStatsField] = []
            if showsDetails, let lead = playback.videoLeadFramesBudget {
                session.append(
                    DeveloperStatsField(
                        key: "Queued ahead",
                        value: String(lead),
                        denominator: playback.videoLeadFramesCeiling.map(String.init)
                    )
                )
            }
            if let buffer = playback.demuxBuffer, buffer.forwardLimitBytes > 0 {
                session.append(
                    DeveloperStatsField(
                        key: "Buffer",
                        value: megabytes(UInt64(max(buffer.forwardBufferedBytes, 0))),
                        unit: "MB",
                        denominator: megabytes(UInt64(max(buffer.forwardLimitBytes, 0)))
                    )
                )
            }
            if playback.nominalFrameRate > 0 {
                session.append(
                    DeveloperStatsField(
                        key: "Enqueued",
                        value: enqueuedSamplesPerSecond.map { String(format: "%.2f", $0) } ?? "—",
                        unit: " frames/s"
                    )
                )
            }
            session.append(DeveloperStatsField(
                key: "Dropped",
                value: playback.rendererDroppedFrameCount.map(String.init) ?? "—",
                unit: " frames"
            ))
            if session.isEmpty == false {
                result.append(DeveloperStatsGroup(id: "session", fields: session))
            }
        }

        result.append(DeveloperStatsGroup(id: "application", fields: memory))
        if showsDetails {
            for start in stride(from: 0, to: memoryDetails.count, by: 3) {
                result.append(DeveloperStatsGroup(
                    id: "memory-details-\(start)",
                    fields: Array(memoryDetails[start..<min(start + 3, memoryDetails.count)])
                ))
            }
        }
        return result
    }

    public static func text(
        metrics: DeveloperProcessMetrics,
        sceneUpdatesPerSecond: Double?,
        enqueuedSamplesPerSecond: Double?,
        playback: PlaybackDiagnostics?,
        sessionIsActive: Bool,
        requestedRefreshHz: Float? = nil,
        requestStatus: String = "Not requested",
        showsDetails: Bool = false
    ) -> String {
        groups(
            metrics: metrics,
            sceneUpdatesPerSecond: sceneUpdatesPerSecond,
            enqueuedSamplesPerSecond: enqueuedSamplesPerSecond,
            playback: playback,
            sessionIsActive: sessionIsActive,
            requestedRefreshHz: requestedRefreshHz,
            requestStatus: requestStatus,
            showsDetails: showsDetails
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
            return DeveloperStatsField(key: "Main-thread stall", value: "0", unit: "ms")
        }
        return DeveloperStatsField(
            key: "Main-thread stall",
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
    private let requestedRefreshHz: Float?
    private let requestStatus: String
    private let showsDetails: Bool

    public init(
        metrics: DeveloperProcessMetrics,
        sceneUpdatesPerSecond: Double? = nil,
        enqueuedSamplesPerSecond: Double? = nil,
        playback: PlaybackDiagnostics? = nil,
        sessionIsActive: Bool = false,
        requestedRefreshHz: Float? = nil,
        requestStatus: String = "Not requested",
        showsDetails: Bool = false
    ) {
        self.metrics = metrics
        self.sceneUpdatesPerSecond = sceneUpdatesPerSecond
        self.enqueuedSamplesPerSecond = enqueuedSamplesPerSecond
        self.playback = playback
        self.sessionIsActive = sessionIsActive
        self.requestedRefreshHz = requestedRefreshHz
        self.requestStatus = requestStatus
        self.showsDetails = showsDetails
    }

    private var groups: [DeveloperStatsGroup] {
        DeveloperStatsLine.groups(
            metrics: metrics,
            sceneUpdatesPerSecond: sceneUpdatesPerSecond,
            enqueuedSamplesPerSecond: enqueuedSamplesPerSecond,
            playback: playback,
            sessionIsActive: sessionIsActive,
            requestedRefreshHz: requestedRefreshHz,
            requestStatus: requestStatus,
            showsDetails: showsDetails
        )
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
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
                sessionIsActive: sessionIsActive,
                requestedRefreshHz: requestedRefreshHz,
                requestStatus: requestStatus,
                showsDetails: showsDetails
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
                && playbackRuntime.activeSessionID != nil,
            requestedRefreshHz: playbackRuntime.displayCriteria.requestedHz,
            requestStatus: playbackRuntime.displayCriteria.statusText,
            showsDetails: developerMetrics.showsDetailedMetrics
        )
    }
}

public extension View {
    func developerStatsOverlay(
        isEnabled: Bool,
        sceneKey: DeveloperMetricsModel.SceneKey? = nil,
        includePlayback: Bool = true
    ) -> some View {
        developerStatsPlacement(aboveWindow: sceneKey == .window, isEnabled: isEnabled) {
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
        sessionIsActive: Bool = false,
        requestedRefreshHz: Float? = nil,
        requestStatus: String = "Not requested",
        showsDetails: Bool = false
    ) -> some View {
        developerStatsPlacement(aboveWindow: true, isEnabled: isEnabled) {
            if isEnabled {
                DeveloperStatsOverlay(
                    metrics: metrics,
                    sceneUpdatesPerSecond: sceneUpdatesPerSecond,
                    enqueuedSamplesPerSecond: enqueuedSamplesPerSecond,
                    playback: playback,
                    sessionIsActive: sessionIsActive,
                    requestedRefreshHz: requestedRefreshHz,
                    requestStatus: requestStatus,
                    showsDetails: showsDetails
                )
                .enchronSpatialFrame(depth: 0)
                .enchronSpatialOffset(z: WindowPlaybackSurfaceGeometry.coincidentChromeDepth)
                .padding(DesignTokens.Spacing.sm)
            }
        }
    }
}

private extension View {
    @ViewBuilder
    func developerStatsPlacement<Content: View>(
        aboveWindow: Bool,
        isEnabled: Bool,
        @ViewBuilder content: () -> Content
    ) -> some View {
#if os(visionOS)
        if aboveWindow {
            ornament(
                visibility: isEnabled ? .visible : .hidden,
                attachmentAnchor: .scene(.top),
                contentAlignment: .bottom
            ) {
                content().padding(.bottom, DesignTokens.Spacing.xl)
            }
        } else {
            overlay(alignment: .bottomTrailing, content: content)
        }
#else
        overlay(alignment: .bottomTrailing, content: content)
#endif
    }
}
#else
import SwiftUI

public struct DeveloperStatsOverlayReader: View {
    public init(
        sceneKey: DeveloperMetricsModel.SceneKey? = nil,
        includePlayback: Bool = true
    ) {}

    public var body: some View { EmptyView() }
}

public extension View {
    func developerStatsOverlay(
        isEnabled: Bool,
        sceneKey: DeveloperMetricsModel.SceneKey? = nil,
        includePlayback: Bool = true
    ) -> some View {
        self
    }
}
#endif
