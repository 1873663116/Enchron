import DesignSystem
import SwiftUI

struct PlaybackEdgeEmphasis: View {
    init() {}

    var body: some View {
        Rectangle()
            .fill(.thickMaterial)
            .mask(verticalFade)
            .frame(maxWidth: .infinity)
            .frame(height: DesignTokens.PlaybackEdge.depth)
            .clipShape(ContainerRelativeShape())
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private var verticalFade: LinearGradient {
        LinearGradient(
            stops: Self.easedStops,
            startPoint: .top,
            endPoint: .bottom
        )
    }

    static let easedStops: [Gradient.Stop] = {
        let hold = DesignTokens.PlaybackEdge.holdFraction
        let samples = 12
        return (0...samples).map { index in
            let location = CGFloat(index) / CGFloat(samples)
            let progress = min(max((location - hold) / (1 - hold), 0), 1)
            let eased = progress * progress * (3 - 2 * progress)
            return .init(color: .white.opacity(1 - eased), location: location)
        }
    }()
}
