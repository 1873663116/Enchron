import SwiftUI
import RealityKit

extension View {
    /// Enables people to drag a RealityKit entity to rotate the scene,
    /// with optional pitch limit and configurable sensitivity.
    ///
    /// Adapted from Apple's HelloWorld DragRotationModifier pattern for
    /// Enchron's immersive/panorama playback modes.
    /// Uses `.interactiveSpring` during drag and `.spring` with predicted
    /// end translation for inertia on release.
    func dragRotation(
        pitchLimit: Angle? = Angle(degrees: 30),
        sensitivity: Double = 0.005
    ) -> some View {
        self.modifier(
            DragRotationModifier(
                pitchLimit: pitchLimit,
                sensitivity: sensitivity
            )
        )
    }
}

/// Converts drag gestures on RealityKit entities into scene rotation,
/// and pinch-to-zoom into scene scale. Drag and Magnify run simultaneously.
private struct DragRotationModifier: ViewModifier {
    var pitchLimit: Angle?
    var sensitivity: Double

    @State private var baseYaw: Double = 0
    @State private var yaw: Double = 0
    @State private var basePitch: Double = 0
    @State private var pitch: Double = 0
    @State private var scale: Double = 1.0
    @State private var startScale: Double?

    func body(content: Content) -> some View {
        content
            .scaleEffect(scale)
            .rotation3DEffect(.radians(yaw == 0 ? 0.01 : yaw), axis: (x: 0, y: 1, z: 0))
            .rotation3DEffect(.radians(pitch == 0 ? 0.01 : pitch), axis: (x: 1, y: 0, z: 0))
            .gesture(DragGesture(minimumDistance: 0.0)
                .targetedToAnyEntity()
                .onChanged { value in
                    let dx = Double(value.translation.width)
                    let dy = Double(value.translation.height)

                    withAnimation(.interactiveSpring) {
                        yaw = spin(displacement: dx, base: baseYaw, limit: nil)
                        pitch = spin(displacement: dy, base: basePitch, limit: pitchLimit)
                    }
                }
                .onEnded { value in
                    let dx = Double(value.translation.width)
                    let dy = Double(value.translation.height)
                    let pdx = Double(value.predictedEndTranslation.width - value.translation.width)
                    let pdy = Double(value.predictedEndTranslation.height - value.translation.height)

                    withAnimation(.spring) {
                        yaw = finalSpin(
                            displacement: dx,
                            predictedDisplacement: pdx,
                            base: baseYaw,
                            limit: nil)
                        pitch = finalSpin(
                            displacement: dy,
                            predictedDisplacement: pdy,
                            base: basePitch,
                            limit: pitchLimit)
                    }

                    baseYaw = yaw
                    basePitch = pitch
                }
            )
            .simultaneousGesture(MagnifyGesture()
                .onChanged { value in
                    let base = startScale ?? scale
                    if startScale == nil { startScale = scale }
                    withAnimation(.interactiveSpring) {
                        scale = max(0.5, min(2.0, value.magnification * base))
                    }
                }
                .onEnded { _ in
                    startScale = nil
                }
            )
    }

    /// Calculates the rotation angle during an active drag.
    /// When limited, uses atan() for rubber-band damping at the edges.
    private func spin(
        displacement: Double,
        base: Double,
        limit: Angle?
    ) -> Double {
        if let limit {
            return atan(displacement * sensitivity) * (limit.degrees / 90)
        } else {
            return base + displacement * sensitivity
        }
    }

    /// Calculates the final rotation with inertia from predicted end translation.
    /// Returns to zero when pitch-limited (spring-back effect).
    private func finalSpin(
        displacement: Double,
        predictedDisplacement: Double,
        base: Double,
        limit: Angle?
    ) -> Double {
        guard limit == nil else { return 0 }

        let cap = .pi * 2.0 / sensitivity
        let delta = displacement + max(-cap, min(cap, predictedDisplacement))

        return base + delta * sensitivity
    }
}
