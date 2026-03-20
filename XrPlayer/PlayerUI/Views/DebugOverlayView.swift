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
                    sectionHeader("HDR Pipeline")

                    VStack(alignment: .leading, spacing: 6) {
                        infoRow("Content", videoViewModel.isHDRContent ? "HDR" : "SDR")
                        infoRow("Output", videoViewModel.hdrOutputMode.rawValue)
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
}
