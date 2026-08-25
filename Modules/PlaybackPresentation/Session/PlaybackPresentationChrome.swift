import PlaybackPresentation
import SwiftUI

enum PlaybackPresentationRendererBindingPolicy {
    static func shouldBindRenderer(
        for presentation: PlaybackPresentation,
        previousPresentation: PlaybackPresentation?,
        targetPresentation: PlaybackPresentation?,
        sourceRendererMayRelease: Bool,
        targetRendererMayBind: Bool
    ) -> Bool {
        guard let previousPresentation,
              let targetPresentation,
              previousPresentation != targetPresentation else {
            return true
        }

        let crossesRealityViewRoots =
            previousPresentation.usesMainWindow
            != targetPresentation.usesMainWindow
        guard crossesRealityViewRoots else {
            return true
        }
        if presentation.usesMainWindow == previousPresentation.usesMainWindow {
            return sourceRendererMayRelease == false
        }
        if presentation.usesMainWindow == targetPresentation.usesMainWindow {
            return targetRendererMayBind
        }
        return false
    }
}

enum PlaybackPresentationTransitionAppearance {
    static let sourceFadeDuration: TimeInterval = 2
    static let rendererTransferDelay: TimeInterval = 0.5
    static let targetFadeDuration: TimeInterval = 0.8
    static let targetPreparationOpacity = 0.001

    static func opacity(
        for hostedPresentation: PlaybackPresentation,
        settledPresentation: PlaybackPresentation,
        transition: PlaybackPresentationTransition?,
        visualCutoverMayBegin: Bool = true
    ) -> Double {
        if let transition {
            if visualCutoverMayBegin == false {
                return hostedPresentation == transition.targetPresentation
                    ? targetPreparationOpacity
                    : 1
            }
            return hostedPresentation == transition.targetPresentation
                ? 1
                : 0
        }
        return hostedPresentation == settledPresentation ? 1 : 0
    }

    static func windowSceneHostOpacity(
        for hostedPresentation: PlaybackPresentation,
        settledPresentation: PlaybackPresentation,
        transition: PlaybackPresentationTransition?,
        visualCutoverMayBegin: Bool = true
    ) -> Double {
        if transition != nil {
            return 1
        }
        return opacity(
            for: hostedPresentation,
            settledPresentation: settledPresentation,
            transition: transition,
            visualCutoverMayBegin: visualCutoverMayBegin
        )
    }

    static func windowVideoEntityOpacity(
        for hostedPresentation: PlaybackPresentation,
        settledPresentation: PlaybackPresentation,
        transition: PlaybackPresentationTransition?,
        visualCutoverMayBegin: Bool
    ) -> Double {
        if let transition,
           hostedPresentation == transition.previousPresentation,
           transition.previousPresentation.usesMainWindow,
           transition.targetPresentation.usesImmersiveSpace {
            return 1
        }
        return opacity(
            for: hostedPresentation,
            settledPresentation: settledPresentation,
            transition: transition,
            visualCutoverMayBegin: visualCutoverMayBegin
        )
    }

    static func shouldAnimateWindowVideoEntity(
        transition: PlaybackPresentationTransition?,
        visualCutoverMayBegin: Bool
    ) -> Bool {
        guard visualCutoverMayBegin,
              let transition,
              transition.previousPresentation == .panorama,
              transition.targetPresentation.usesMainWindow else {
            return true
        }
        return false
    }

    static func acceptsInput(
        for hostedPresentation: PlaybackPresentation,
        settledPresentation: PlaybackPresentation,
        transition: PlaybackPresentationTransition?
    ) -> Bool {
        transition == nil && hostedPresentation == settledPresentation
    }

    static func animation(for targetOpacity: Double) -> Animation {
        .easeInOut(
            duration: targetOpacity == 0
                ? sourceFadeDuration
                : targetFadeDuration
        )
    }
}
