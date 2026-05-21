import SwiftUI

/// Debug panel showing current playback pipeline state.
/// Saturation adjustment will be implemented via a unified
/// RealityKit compute shader path in a future iteration.
public struct DebugOverlayView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(WindowVideoViewModel.self) private var videoViewModel

    let onClose: () -> Void

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Debug Info")
                    .font(.headline)
                Spacer()
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    sectionHeader("Renderer")

                    VStack(alignment: .leading, spacing: 8) {
                        Picker("Renderer", selection: rendererBinding) {
                            ForEach(WindowVideoViewModel.DiagnosticRenderer.allCases, id: \.self) { renderer in
                                Text(renderer.rawValue).tag(renderer)
                            }
                        }
                        .pickerStyle(.segmented)
                        .accessibilityIdentifier("HDRDiagnostics-RendererSwitch")
                        .accessibilityLabel("Renderer")

                        infoRow("Role", rendererRole)
                    }
                    .padding(.horizontal, 16)

                    Divider().padding(.vertical, 4)

                    sectionHeader("HDR Pipeline")

                    VStack(alignment: .leading, spacing: 6) {
                        infoRow("Source", sourceHDRLabel)
                        infoRow(
                            "Output",
                            PlaybackInfoFormatter.hdrOutputDescription(videoViewModel.hdrOutputMode)
                        )
                        if let profile = videoViewModel.displayMediaProfile {
                            infoRow("HDR Type", profile.hdrType.rawValue)
                            infoRow(
                                "Resolution",
                                "\(profile.resolution.width)\u{00D7}\(profile.resolution.height)"
                            )
                            infoRow("Frame Rate", String(format: "%.2f", profile.frameRate))
                        }
                        infoRow("Mode", appModel.playbackMode.rawValue)
                    }
                    .padding(.horizontal, 16)

                    Divider().padding(.vertical, 4)

                    sectionHeader("HDR Probe")

                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 10) {
                            Button("Synthetic") {
                                videoViewModel.sampleSyntheticHDRProbe()
                            }
                            .accessibilityIdentifier("HDRDiagnostics-SyntheticSample")
                            .accessibilityLabel("Sample synthetic EDR pattern")

                            Button("Sample") {
                                Task { await videoViewModel.sampleCurrentHDRDrawable() }
                            }
                            .accessibilityIdentifier("HDRDiagnostics-SampleDrawable")
                            .accessibilityLabel("Sample current MPV drawable")
                        }
                        .buttonStyle(.bordered)

                        if let sample = videoViewModel.latestHDRProbeSample {
                            infoRow("Format", sample.pixelFormat)
                            infoRow("Colorspace", sample.colorspace)
                            infoRow("maxRGB", format(sample.statistics.maxRGB.maxChannel))
                            infoRow("p99Y", format(sample.statistics.p99Luminance))
                            infoRow(">1", "\(sample.statistics.countAbove1)")
                            infoRow(">2", "\(sample.statistics.countAbove2)")
                            infoRow("Pixels", "\(sample.statistics.sampledPixelCount)")
                        } else {
                            infoRow("Status", "not sampled")
                        }

                        if let delta = videoViewModel.hdrProbeDelta {
                            infoRow("Δ max", format(delta.maxRGBDelta))
                            infoRow("Δ p99Y", format(delta.p99LuminanceDelta))
                            infoRow("Δ >1", "\(delta.countAbove1Delta)")
                        } else {
                            infoRow("Δ ON/OFF", "needs both samples")
                        }

                        if let error = videoViewModel.lastHDRProbeError {
                            infoRow("Probe", error)
                        }
                    }
                    .padding(.horizontal, 16)

                    Divider().padding(.vertical, 4)

                    sectionHeader("Apple Reference")

                    VStack(alignment: .leading, spacing: 6) {
                        infoRow("Eligible", boolLabel(videoViewModel.avReferenceMetadata.eligibleForHDRPlayback))
                        infoRow("Track HDR", boolLabel(videoViewModel.avReferenceMetadata.containsHDRVideo))
                        infoRow("Transfer", videoViewModel.avReferenceMetadata.transferFunction ?? "unknown")
                        infoRow("Primaries", videoViewModel.avReferenceMetadata.colorPrimaries ?? "unknown")
                        infoRow("Matrix", videoViewModel.avReferenceMetadata.yCbCrMatrix ?? "unknown")
                        infoRow("Status", videoViewModel.avReferenceMetadata.status)
                    }
                    .padding(.horizontal, 16)

                    Divider().padding(.vertical, 4)

                    sectionHeader("Rendering")

                    VStack(alignment: .leading, spacing: 6) {
                        infoRow(
                            "GPU Path",
                            videoViewModel.usesNativeGPUOutput ? "gpu-next" : "software"
                        )
                        infoRow(
                            "Immersive",
                            appModel.immersiveSpaceState == .open ? "open" : "closed"
                        )
                        infoRow("Display", "measured: no")
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.bottom, 12)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .glassBackgroundEffect()
    }

    @ViewBuilder
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.top, 4)
    }

    @ViewBuilder
    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)
            Text(value)
                .font(.caption.monospaced())
                .foregroundStyle(.primary)
        }
    }

    private var rendererBinding: Binding<WindowVideoViewModel.DiagnosticRenderer> {
        Binding(
            get: { videoViewModel.diagnosticRenderer },
            set: { videoViewModel.setDiagnosticRenderer($0) }
        )
    }

    private var rendererRole: String {
        switch videoViewModel.diagnosticRenderer {
        case .mpv:
            return "primary output path"
        case .apple:
            return "system reference only"
        }
    }

    private var sourceHDRLabel: String {
        guard let hdrType = videoViewModel.displayMediaProfile?.hdrType else {
            return videoViewModel.isHDRContent ? "detected" : "unknown"
        }
        switch hdrType {
        case .sdr:
            return "SDR"
        case .hdr10:
            return "HDR10 detected"
        case .hdr10Plus:
            return "HDR10+ source detected"
        case .dolbyVision:
            return "Dolby Vision source detected"
        case .hlg:
            return "HLG detected"
        }
    }

    private func boolLabel(_ value: Bool?) -> String {
        switch value {
        case .some(true): return "yes"
        case .some(false): return "no"
        case .none: return "unknown"
        }
    }

    private func format(_ value: Double) -> String {
        String(format: "%.3f", value)
    }
}
