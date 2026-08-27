import DesignSystem
import SwiftUI

struct PlaybackEdgeEmphasis: View {
    init() {}

    var body: some View {
        Rectangle()
            .fill(.black)
            .mask(verticalFade)
            .mask(horizontalFade)
            .opacity(DesignTokens.PlaybackEdge.peakOpacity)
            .blur(radius: DesignTokens.PlaybackEdge.blurRadius)
            .padding(DesignTokens.PlaybackEdge.blurRadius)
            .frame(maxWidth: .infinity)
            .frame(height: DesignTokens.PlaybackEdge.depth)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private var verticalFade: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: .white, location: 0),
                .init(
                    color: .white.opacity(
                        DesignTokens.PlaybackEdge.midOpacity
                            / max(DesignTokens.PlaybackEdge.peakOpacity, 0.001)
                    ),
                    location: DesignTokens.PlaybackEdge.midLocation
                ),
                .init(color: .clear, location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var horizontalFade: some View {
        HStack(spacing: 0) {
            LinearGradient(
                colors: [.clear, .white],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: DesignTokens.PlaybackEdge.sideFadeWidth)
            Color.white
            LinearGradient(
                colors: [.white, .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: DesignTokens.PlaybackEdge.sideFadeWidth)
        }
    }
}
