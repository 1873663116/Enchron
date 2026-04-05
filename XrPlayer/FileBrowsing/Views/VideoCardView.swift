import SwiftUI

/// A card component displaying a video file with thumbnail placeholder,
/// format badges, and metadata. Designed for LazyVGrid display.
///
/// Badge Z offsets create parallax bounce on visionOS hover (system behavior).
struct VideoCardView: View {
    let file: FileBrowsingDomain.MediaFile
    let watchedSeconds: Double?
    let onTap: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter
    }()

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                thumbnailArea
                metadataArea
            }
        }
        .buttonStyle(.plain)
        .contentShape(.rect(cornerRadius: DesignTokens.Radius.card))
        .hoverEffect(reduceMotion ? .highlight : .lift)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint("Opens video details")
    }

    // MARK: - Thumbnail

    private var thumbnailArea: some View {
        ZStack {
            // Placeholder thumbnail (16:9 aspect)
            RoundedRectangle(cornerRadius: DesignTokens.Radius.card, style: .continuous)
                .fill(Color.enchronSurfaceContainerHighest)
                .aspectRatio(16.0 / 9.0, contentMode: .fit)
                .overlay {
                    Image(systemName: fileIcon)
                        .font(.system(size: 36))
                        .foregroundStyle(Color.enchronOnSurfaceVariant.opacity(0.5))
                }

            // Format badge (top-left)
            if let formatText = formatBadgeText {
                VStack {
                    HStack {
                        badgeLabel(formatText)
                            .offset(z: 4)
                        Spacer()
                    }
                    Spacer()
                }
                .padding(10)
            }

            // Duration badge (bottom-right) — uses file size as proxy since duration is unavailable
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    badgeLabel(byteFormatter.string(fromByteCount: file.sizeInBytes))
                        .offset(z: 8)
                }
            }
            .padding(10)

            // Watched progress bar
            if let seconds = watchedSeconds, seconds > 0 {
                VStack {
                    Spacer()
                    ProgressView(value: min(seconds / 3600.0, 1.0))
                        .tint(.orange)
                        .padding(.horizontal, 6)
                        .padding(.bottom, 4)
                }
            }
        }
    }

    // MARK: - Metadata

    private var metadataArea: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(file.name)
                .font(DesignTokens.Typography.headline)
                .lineLimit(2)
                .truncationMode(.tail)

            HStack(spacing: 4) {
                Text(file.fileExtension.uppercased())
                Text("\u{00B7}")
                Text(formattedDate)
            }
            .font(DesignTokens.Typography.metadata)
            .foregroundStyle(Color.enchronOnSurfaceVariant)

            if let seconds = watchedSeconds, seconds > 0 {
                HStack(spacing: 4) {
                    Circle()
                        .fill(.orange)
                        .frame(width: 6, height: 6)
                    Text("Watched \(Self.formatTime(seconds))")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Badge

    private func badgeLabel(_ text: String) -> some View {
        Text(text)
            .font(DesignTokens.Typography.badge)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.enchronTertiary, in: Capsule())
            .foregroundStyle(Color.enchronOnTertiary)
    }

    // MARK: - Helpers

    private var fileIcon: String {
        switch file.fileExtension {
        case "mp4", "mov", "m4v":
            return "video.fill"
        case "mkv", "webm", "avi":
            return "film.fill"
        default:
            return "doc.fill"
        }
    }

    /// Heuristic format badge based on file extension (MediaFile lacks resolution/HDR attributes).
    private var formatBadgeText: String? {
        switch file.fileExtension {
        case "mov":
            return "ProRes"
        case "mkv":
            return "MKV"
        case "webm":
            return "WebM"
        default:
            return nil
        }
    }

    private var formattedDate: String {
        file.modifiedAt.formatted(date: .abbreviated, time: .omitted)
    }

    private var accessibilityText: String {
        var parts = ["Video: \(file.name)"]
        parts.append(byteFormatter.string(fromByteCount: file.sizeInBytes))
        parts.append(file.fileExtension.uppercased())
        if let badge = formatBadgeText {
            parts.append(badge)
        }
        if let seconds = watchedSeconds, seconds > 0 {
            parts.append("watched \(Self.formatTime(seconds))")
        }
        return parts.joined(separator: ", ")
    }

    private static func formatTime(_ totalSeconds: Double) -> String {
        let seconds = Int(totalSeconds)
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }
}
