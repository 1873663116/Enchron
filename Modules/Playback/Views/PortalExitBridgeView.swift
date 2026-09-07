import CoreGraphics
import SwiftUI

public struct PortalExitBridgeView: View {
    private let frame: CGImage?
    private let targetIsRevealed: Bool
    @State private var shownFrame: CGImage?
    @State private var opacity: Double = 1
    @State private var isFadingOut = false

    public init(frame: CGImage?, targetIsRevealed: Bool) {
        self.frame = frame
        self.targetIsRevealed = targetIsRevealed
    }

    public var body: some View {
        ZStack {
            if let shownFrame {
                Image(shownFrame, scale: 1, label: Text(""))
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    .opacity(opacity)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .onChange(of: frame.map(ObjectIdentifier.init), initial: true) { _, _ in
            synchronizeFrame()
        }
        .onChange(of: targetIsRevealed, initial: true) { _, revealed in
            guard revealed else { return }
            fadeOut()
        }
    }

    private func synchronizeFrame() {
        guard let frame else {
            guard isFadingOut == false else { return }
            shownFrame = nil
            return
        }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            shownFrame = frame
            opacity = SpatialPlatformImmersiveExitWindowRevealPolicy
                .lastFrameBridgeOpacity(targetIsRevealed: false)
            isFadingOut = false
        }
        if targetIsRevealed {
            fadeOut()
        }
    }

    private func fadeOut() {
        guard shownFrame != nil, isFadingOut == false else { return }
        isFadingOut = true
        withAnimation(PlaybackPresentationTransitionAppearance.targetFadeAnimation) {
            opacity = SpatialPlatformImmersiveExitWindowRevealPolicy
                .lastFrameBridgeOpacity(targetIsRevealed: true)
        } completion: {
            shownFrame = nil
            isFadingOut = false
        }
    }
}
