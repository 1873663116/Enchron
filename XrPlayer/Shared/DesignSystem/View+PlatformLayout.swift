import SwiftUI

extension View {
    @ViewBuilder
    func enchronSpatialOffset(z: CGFloat) -> some View {
        #if os(visionOS)
        offset(z: z)
        #else
        self
        #endif
    }

    @ViewBuilder
    func enchronSpatialFrame(depth: CGFloat) -> some View {
        #if os(visionOS)
        frame(depth: depth)
        #else
        self
        #endif
    }
}
