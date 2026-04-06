import SwiftUI

/// Placeholder card displayed in the grid while a data source is connecting.
/// Mirrors the visual structure of `VideoCardView` using `redacted(reason: .placeholder)`.
struct SkeletonCardView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Thumbnail placeholder (16:9 aspect ratio, matches VideoCardView)
            RoundedRectangle(cornerRadius: DesignTokens.Radius.card, style: .continuous)
                .fill(Color.enchronSurfaceContainerHighest)
                .aspectRatio(16.0 / 9.0, contentMode: .fit)

            // Metadata placeholder rows
            VStack(alignment: .leading, spacing: 6) {
                Text("Placeholder filename that is long")
                    .font(DesignTokens.Typography.headline)
                    .lineLimit(2)

                Text("Placeholder · Jan 1, 2026")
                    .font(DesignTokens.Typography.metadata)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(minHeight: 80, alignment: .top)
            .redacted(reason: .placeholder)
        }
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.card, style: .continuous)
                .stroke(Color.white.opacity(0.05), lineWidth: 0.5)
        )
        .accessibilityHidden(true)
    }
}
