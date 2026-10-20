import Foundation
import Playback

@MainActor
extension SessionSnapshot {
    public var streamingPlaybackInformation: StreamingPlaybackInformation {
        let configuration = negotiated
        let width = configuration?.width ?? requested.streamWidth
        let height = configuration?.height ?? requested.streamHeight
        let frameRate = configuration?.frameRate ?? requested.frameRate
        let configuredBitrate = configuration?.bitrateKbps ?? requested.bitrateKbps
        let codec = codecLabel(configuration?.codec, preference: requested.codec)
        let hdr = hdrLabel(
            (configuration?.hostHdrActive ?? hdrModeReported)
        )
        let measured = diagnostics.measuredBitrateKbps

        let network = [
            measured.map {
                "\(bitrateMbps($0)) / \(bitrateMbps(configuredBitrate)) Mbps"
            } ?? "\(bitrateMbps(configuredBitrate)) Mbps",
            diagnostics.estimatedRttMs.map { "RTT \($0) ms" },
            "drops \(diagnostics.networkDroppedFrames)"
        ].compactMap { $0 }.joined(separator: " · ")

        let format = [
            "\(width)×\(height)",
            "\(frameRate) fps",
            hdr,
            codec
        ].joined(separator: " · ")

        return StreamingPlaybackInformation(
            title: "\(hostName) · \(appName)",
            leadingLabel: network,
            trailingLabel: format,
            details: detailRows(configuration: configuration)
        )
    }

    private func detailRows(
        configuration: NegotiatedStreamConfiguration?
    ) -> [StreamingPlaybackInformation.Detail] {
        var rows: [StreamingPlaybackInformation.Detail] = [
            .init(id: "host", title: "Host", value: hostName),
            .init(id: "application", title: "Application", value: appName),
            .init(id: "session", title: "Session", value: state.readableValue),
            .init(
                id: "requested",
                title: "Requested",
                value: requestedLabel
            )
        ]
        if let configuration {
            rows.append(
                .init(
                    id: "negotiated",
                    title: "Negotiated",
                    value: negotiatedLabel(configuration)
                )
            )
        } else {
            rows.append(
                .init(
                    id: "negotiated",
                    title: "Negotiated",
                    value: "unavailable"
                )
            )
        }
        rows.append(
            .init(
                id: "measuredBitrate",
                title: "Measured bitrate",
                value: diagnostics.measuredBitrateKbps.map {
                    "\(bitrateMbps($0)) Mbps"
                } ?? "unavailable"
            )
        )
        rows.append(
            .init(
                id: "presentedFrameRate",
                title: "Presented frame rate",
                value: diagnostics.presentedFramesPerSecond.map {
                    "\($0) fps"
                } ?? "unavailable"
            )
        )
        rows.append(
            .init(
                id: "roundTripTime",
                title: "Round-trip time",
                value: diagnostics.estimatedRttMs.map { milliseconds in
                    if let variance = diagnostics.estimatedRttVarianceMs {
                        return "\(milliseconds) ms ±\(variance) ms"
                    }
                    return "\(milliseconds) ms"
                } ?? "unavailable"
            )
        )
        rows.append(
            .init(
                id: "droppedFrames",
                title: "Dropped frames",
                value: "\(diagnostics.networkDroppedFrames)"
            )
        )
        rows.append(
            .init(
                id: "queueDepth",
                title: "Queue depth",
                value: "\(diagnostics.queueDepth)"
            )
        )
        rows.append(
            .init(
                id: "decodeRecoveries",
                title: "Decode recoveries",
                value: "\(diagnostics.decodeRecoveries)"
            )
        )
        rows.append(
            .init(
                id: "keyframeRequests",
                title: "Keyframe requests",
                value: "\(diagnostics.idrRequests)"
            )
        )
        rows.append(
            .init(
                id: "packetsReceived",
                title: "Packets received",
                value: "\(diagnostics.packetsReceived)"
            )
        )
        rows.append(
            .init(
                id: "audio",
                title: "Audio",
                value: "host \(diagnostics.hostAudioPlaying ? "playing" : "idle")"
                    + " · client \(diagnostics.clientAudioOutput ? "on" : "off")"
            )
        )
        return rows
    }

    private var requestedLabel: String {
        [
            "\(requested.streamWidth)×\(requested.streamHeight)",
            "\(requested.frameRate) fps",
            "\(bitrateMbps(requested.bitrateKbps)) Mbps",
            codecLabel(nil, preference: requested.codec),
            requested.hdrEnabled ? "HDR" : "SDR"
        ].joined(separator: " · ")
    }

    private func negotiatedLabel(
        _ configuration: NegotiatedStreamConfiguration
    ) -> String {
        [
            "\(configuration.width)×\(configuration.height)",
            "\(configuration.frameRate) fps",
            "\(bitrateMbps(configuration.bitrateKbps)) Mbps",
            configuration.codec.displayName,
            hdrLabel(configuration.hostHdrActive)
        ].joined(separator: " · ")
    }
}

private func bitrateMbps(_ kbps: Int) -> String {
    let mbps = Double(kbps) / 1000
    if mbps >= 10 {
        return String(format: "%.0f", mbps)
    }
    return String(format: "%.1f", mbps)
}

private func hdrLabel(_ isHDR: Bool) -> String {
    isHDR ? "HDR" : "SDR"
}

private func codecLabel(
    _ codec: StreamVideoCodec?,
    preference: StreamCodecPreference
) -> String {
    if let codec {
        return codec.displayName
    }
    switch preference {
    case .auto: return "Auto"
    case .hevc: return "HEVC"
    case .h264: return "H.264"
    case .av1: return "AV1"
    }
}
